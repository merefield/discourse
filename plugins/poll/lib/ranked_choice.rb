# frozen_string_literal: true

class DiscoursePoll::RankedChoice
  MAX_ROUNDS = 50
  SANKEY_COLOUR_SATURATION = 70.0
  SANKEY_COLOUR_LIGHTNESS = 50.0

  def self.outcome(poll_id)
    options = PollOption.where(poll_id: poll_id).map { |hash| { id: hash.digest, html: hash.html } }

    ballot = []

    #Fetch all votes for the poll in a single query
    votes =
      PollVote
        .where(poll_id: poll_id)
        .select(:user_id, :poll_option_id, :rank)
        .order(:user_id, :rank)
        .includes(:poll_option) # Eager load poll options
    # Group votes by user_id
    votes_by_user = votes.group_by(&:user_id)
    # Build the ballot
    votes_by_user.each do |user_id, user_votes|
      ballot_paper =
        user_votes.select { |vote| vote.rank > 0 }.map { |vote| vote.poll_option.digest }
      ballot << ballot_paper
    end
    DiscoursePoll::RankedChoice.run(ballot, options) if ballot.length > 0
  end

  def self.run(starting_votes, options)
    current_votes = starting_votes
    round_activity = []
    potential_winners = []
    round = 0
    node_key_index = 0
    sankey_nodes = []
    sankey_colours = get_sankey_colours(options)
    sankey_labels = {}
    while round < MAX_ROUNDS
      round += 1

      # Count the first place votes for each candidate
      tally = tally_votes(current_votes)

      max_votes = tally.values.max

      # Find the candidate(s) with the most votes
      potential_winners = find_potential_winners(tally, max_votes)

      # Check for a majority and return if found
      if majority_check(tally, max_votes)
        majority_candidate = enrich(potential_winners.keys.first, options)

        round_activity << { round: round, majority: majority_candidate, eliminated: nil }

        return(
          {
            tied: false,
            tied_candidates: nil,
            winner: true,
            winning_candidate: majority_candidate,
            round_activity: round_activity,
            sankey_data: {
              sankey_nodes: sankey_nodes,
              sankey_labels: sankey_labels,
              sankey_colours: sankey_colours,
            },
          }
        )
      end

      # Find the candidate(s) with the least votes
      losers = identify_losers(tally)

      # Collect flow data before eliminating candidates
      round_flows = Hash.new { |h, k| h[k] = Hash.new(0) }

      current_votes.each do |vote|
        if losers.include?(vote.first)
          from_candidate = vote.first + "_" + round.to_s
          updated_vote = vote.reject { |candidate| losers.include?(candidate) }
          next if updated_vote.empty?
          to_candidate = updated_vote.first + "_" + (round + 1).to_s
          round_flows[from_candidate][to_candidate] += 1
        else
          from_candidate = vote.first + "_" + round.to_s
          to_candidate = vote.first + "_" + (round + 1).to_s
          round_flows[from_candidate][to_candidate] += 1
        end
      end

      # Process round_flows to create sankey_data entries
      round_flows.each do |from_candidate, to_candidate|
        flow = to_candidate.first[1]
        to_candidate_digest = to_candidate.keys.first
        sankey_nodes << { from: from_candidate, to: to_candidate_digest, flow: flow }
        from_html = enrich(from_candidate.split("_").first, options)[:html]
        from_hash = { "#{from_candidate}": from_html }
        key_to_check = from_hash.keys.first
        sankey_labels.merge!(from_hash) unless sankey_labels.key?(key_to_check)
        to_html = enrich(to_candidate_digest.split("_").first, options)[:html]
        to_hash = { "#{to_candidate_digest}": to_html }
        key_to_check = to_hash.keys.first
        sankey_labels.merge!(to_hash) unless sankey_labels.key?(key_to_check)
      end

      # Remove the candidate with the least votes
      current_votes.each { |vote| vote.reject! { |candidate| losers.include?(candidate) } }

      losers = losers.map { |loser| enrich(loser, options) }

      round_activity << { round: round, majority: nil, eliminated: losers }

      all_empty = current_votes.all? { |arr| arr.empty? }

      if all_empty
        return(
          {
            tied: true,
            tied_candidates: losers,
            winner: nil,
            winning_candidate: nil,
            round_activity: round_activity,
            sankey_data: {
              sankey_nodes: sankey_nodes,
              sankey_labels: sankey_labels,
              sankey_colours: sankey_colours,
            },
          }
        )
      end
    end

    potential_winners =
      potential_winners.keys.map { |potential_winner| enrich(potential_winner, options) }

    {
      tied: true,
      tied_candidates: potential_winners,
      winner: nil,
      winning_candidate: nil,
      round_activity: round_activity,
      sankey_data: {
        sankey_nodes: sankey_nodes,
        sankey_labels: sankey_labels,
        sankey_colours: sankey_colours,
      },
    }
  end

  private

  def self.generate_node_key(n)
    key = ""
    while n >= 0
      key.prepend((97 + n % 26).chr) # 97 is ASCII code for 'a'
      n = n / 26 - 1
    end
    key
  end

  def self.tally_votes(current_votes)
    tally = Hash.new(0)
    current_votes.each do |vote|
      vote.each { |candidate| tally[candidate] = 0 unless tally.has_key?(candidate) }
    end
    current_votes.each { |vote| tally[vote.first] += 1 if vote.first }
    tally
  end

  def self.find_potential_winners(tally, max_votes)
    tally.select { |k, v| v == max_votes }
  end

  def self.majority_check(tally, max_votes)
    total_votes = tally.values.sum

    max_votes && max_votes > total_votes / 2
  end

  def self.identify_losers(tally)
    min_votes = tally.values.min

    tally.select { |k, v| v == min_votes }.keys
  end

  def self.enrich(digest, options)
    { digest: digest, html: options.find { |option| option[:id] == digest }[:html] }
  end

  def self.hue2rgb(p, q, t)
    t += 1 if t < 0
    t -= 1 if t > 1

    if t < 1.0 / 6
      p + (q - p) * 6 * t
    elsif t < 1.0 / 2
      q
    elsif t < 2.0 / 3
      p + (q - p) * (2.0 / 3 - t) * 6
    else
      p
    end
  end

  def self.hsl_to_rgb(h, s, l)
    h /= 360.0 # Normalize h to [0, 1]
    s /= 100.0 # Normalize s to [0, 1]
    l /= 100.0 # Normalize l to [0, 1]

    if s == 0
      r = g = b = l * 255
    else
      q = l < 0.5 ? l * (1 + s) : l + s - l * s
      p = 2 * l - q
      r = hue2rgb(p, q, h + 1.0 / 3) * 255
      g = hue2rgb(p, q, h) * 255
      b = hue2rgb(p, q, h - 1.0 / 3) * 255
    end

    [r.round, g.round, b.round]
  end

  def self.get_sankey_colours(options)
    # Generate unique colors for each option
    n = options.length
    options.each_with_index do |option, i|
      hue = i * (360.0 / n)
      r, g, b = hsl_to_rgb(hue, SANKEY_COLOUR_SATURATION, SANKEY_COLOUR_LIGHTNESS)
      color = sprintf("#%02X%02X%02X", r, g, b)
      option[:color] = color
    end

    # Output the options with colors
    options
  end
end
