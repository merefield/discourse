import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import round from "discourse/lib/round";
import I18n from "discourse-i18n";
import PollBreakdownModal from "../components/modal/poll-breakdown";
import { PIE_CHART_TYPE } from "../components/modal/poll-ui-builder";
import PollButtonsDropdown from "../components/poll-buttons-dropdown";
import PollInfo from "../components/poll-info";
import PollOptions from "../components/poll-options";
import PollResultsPie from "../components/poll-results-pie";
import PollResultsTabs from "../components/poll-results-tabs";

const FETCH_VOTERS_COUNT = 25;
const STAFF_ONLY = "staff_only";
const MULTIPLE = "multiple";
const NUMBER = "number";
const REGULAR = "regular";
const RANKED_CHOICE = "ranked_choice";
const ON_VOTE = "on_vote";
const ON_CLOSE = "on_close";
const CLOSED = "closed";

export default class PollComponent extends Component {
  @service currentUser;
  @service appEvents;
  @service dialog;
  @service modal;

  @tracked vote = this.args.attrs.vote;
  @tracked status = this.args.attrs.poll.status;
  @tracked
  closed = this.args.attrs.poll.status === CLOSED || this.isAutomaticallyClosed;
  @tracked hasSavedVote = this.args.attrs.hasSavedVote;
  @tracked showResults = this.defaultShowResults();
  @tracked preloadedVoters = this.defaultPreloadedVoters();

  poll = this.args.attrs.poll;
  id = this.args.attrs.id;
  post = this.args.attrs.post;
  titleHTML = this.args.attrs.titleHTML;
  isRankedChoice = this.args.attrs.poll.type === RANKED_CHOICE;
  isMultiple = this.args.attrs.poll.type === MULTIPLE;
  isNumber = this.args.attrs.poll.type === NUMBER;
  groupableUserFields = this.args.attrs.groupableUserFields;

  checkUserGroups = (user, poll) => {
    const pollGroups =
      poll && poll.groups && poll.groups.split(",").map((g) => g.toLowerCase());

    if (!pollGroups) {
      return true;
    }

    const userGroups =
      user && user.groups && user.groups.map((g) => g.name.toLowerCase());

    return userGroups && pollGroups.some((g) => userGroups.includes(g));
  };

  @action
  castVotes() {
    return ajax("/polls/vote", {
      type: "PUT",
      data: {
        post_id: this.post.id,
        poll_name: this.poll.name,
        options: this.vote,
      },
    })
      .then(({ poll }) => {
        this.hasSavedVote = true;
        this.poll.setProperties(poll);
        this.appEvents.trigger("poll:voted", poll, this.post, this.vote);

        if (this.poll.results !== "on_close") {
          this.showResults = true;
        }
        if (this.poll.results === "staff_only") {
          if (this.currentUser && this.currentUser.staff) {
            this.showResults = true;
          } else {
            this.showResults = false;
          }
        }
      })
      .catch((error) => {
        if (error) {
          if (!this.isMultiple && !this.isRankedChoice) {
            this.vote = [...this.vote];
          }
          popupAjaxError(error);
        } else {
          this.dialog.alert(I18n.t("poll.error_while_casting_votes"));
        }
      });
  }

  areRanksValid = (arr) => {
    let ranks = new Set(); // Using a Set to keep track of unique ranks
    let hasNonZeroDuplicate = false;

    arr.forEach((obj) => {
      const rank = obj.rank;

      if (rank !== 0) {
        if (ranks.has(rank)) {
          hasNonZeroDuplicate = true;
          return; // Exit forEach loop if a non-zero duplicate is found
        }
        ranks.add(rank);
      }
    });

    return !hasNonZeroDuplicate;
  };
  get options() {
    return this.args.attrs.poll.options;
  }

  get enrichedOptions() {
    let enrichedOptions = this.options;

    if (this.isRankedChoice) {
      enrichedOptions.forEach((candidate) => {
        const chosenIdx = this.vote.findIndex(
          (object) => object.digest === candidate.id
        );
        if (chosenIdx === -1) {
          candidate.rank = 0;
        } else {
          candidate.rank = this.vote[chosenIdx].rank;
        }
      });
    }

    return enrichedOptions;
  }

  get voters() {
    return this.args.attrs.poll.voters;
  }

  get rankedChoiceOutcome() {
    return this.args.attrs.poll.ranked_choice_outcome || [];
  }

  defaultShowResults() {
    const closed = this.closed;
    const staffOnly = this.staffOnly;
    const topicArchived = this.topicArchived;
    const resultsOnClose = this.args.attrs.poll.results === ON_CLOSE;

    return (
      !(resultsOnClose && !closed) &&
      (this.args.attrs.hasSavedVote ||
        (resultsOnClose && closed) ||
        (topicArchived && !staffOnly) ||
        (closed && !staffOnly))
    );
  }

  defaultPreloadedVoters() {
    let preloadedVoters = {};

    if (this.args.attrs.poll.public && this.args.attrs.poll.preloaded_voters) {
      Object.keys(this.args.attrs.poll.preloaded_voters).forEach((key) => {
        preloadedVoters[key] = {
          voters: this.args.attrs.poll.preloaded_voters[key],
          loading: false,
        };
      });
    }

    this.options.forEach((option) => {
      if (!preloadedVoters[option.id]) {
        preloadedVoters[option.id] = {
          voters: [],
          loading: false,
        };
      }
    });

    return preloadedVoters;
  }

  get topicArchived() {
    return this.args.attrs.post.get("topic.archived");
  }

  get staffOnly() {
    return this.args.attrs.poll.results === STAFF_ONLY;
  }

  get rankedChoiceDropdownContent() {
    let rankedChoiceDropdownContent = [];

    rankedChoiceDropdownContent.push({
      id: 0,
      name: I18n.t("poll.options.ranked_choice.abstain"),
    });

    this.args.attrs.poll.options.forEach((option, i) => {
      option.rank = 0;
      rankedChoiceDropdownContent.push({
        id: i + 1,
        name: (i + 1).toString(),
      });
    });

    return rankedChoiceDropdownContent;
  }

  get isAutomaticallyClosed() {
    const poll = this.args.attrs.poll;
    return (
      (poll.close ?? false) &&
      moment.utc(poll.close, "YYYY-MM-DD HH:mm:ss Z") <= moment()
    );
  }

  get min() {
    let min = parseInt(this.args.attrs.poll.min, 10);
    if (isNaN(min) || min < 0) {
      min = 1;
    }

    return min;
  }

  get max() {
    let max = parseInt(this.args.attrs.poll.max, 10);
    const numOptions = this.args.attrs.poll.options.length;
    if (isNaN(max) || max > numOptions) {
      max = numOptions;
    }
    return max;
  }

  get hasVoted() {
    return this.vote && this.vote.length > 0;
  }

  get hideResultsDisabled() {
    return !this.staffOnly && (this.closed || this.topicArchived);
  }

  @action
  toggleOption(option, rank = 0) {
    let vote = this.vote;

    if (this.isMultiple) {
      const chosenIdx = vote.indexOf(option.id);

      if (chosenIdx !== -1) {
        vote.splice(chosenIdx, 1);
      } else {
        vote.push(option.id);
      }
    } else if (this.isRankedChoice) {
      this.options.forEach((candidate) => {
        const chosenIdx = vote.findIndex(
          (object) => object.digest === candidate.id
        );

        if (chosenIdx === -1) {
          vote.push({
            digest: candidate.id,
            rank: candidate.id === option ? rank : 0,
          });
        } else {
          if (candidate.id === option) {
            vote[chosenIdx].rank = rank;
          }
        }
      });
    } else {
      vote = [option.id];
    }

    this.vote = [...vote];
  }

  @action
  toggleResults() {
    const showResults = !this.showResults;
    this.showResults = showResults;
  }

  get canCastVotes() {
    if (this.closed || !this.currentUser) {
      return false;
    }

    const selectedOptionCount = this.vote?.length || 0;

    if (this.isMultiple) {
      return selectedOptionCount >= this.min && selectedOptionCount <= this.max;
    }

    if (this.isRankedChoice) {
      return (
        this.options.length === this.vote.length &&
        this.areRanksValid(this.vote)
      );
    }

    return selectedOptionCount > 0;
  }

  get notInVotingGroup() {
    return !this.checkUserGroups(this.currentUser, this.poll);
  }

  get pollGroups() {
    return I18n.t("poll.results.groups.title", {
      groups: this.poll.groups,
    });
  }

  get showCastVotesButton() {
    return (this.isMultiple || this.isRankedChoice) && !this.showResults;
  }

  get castVotesButtonClass() {
    return `btn cast-votes ${
      this.canCastVotes ? "btn-primary" : "btn-default"
    }`;
  }

  get castVotesButtonIcon() {
    return !this.castVotesDisabled ? "check" : "far-square";
  }

  get castVotesDisabled() {
    return !this.canCastVotes;
  }

  get showHideResultsButton() {
    return this.showResults && !this.hideResultsDisabled;
  }

  get showShowResultsButton() {
    return (
      !this.showResults &&
      !this.hideResultsDisabled &&
      !(this.poll.results === ON_VOTE && !this.hasSavedVote && !this.isMe) &&
      !(this.poll.results === ON_CLOSE && !this.closed) &&
      !(this.poll.results === STAFF_ONLY && !this.isStaff) &&
      this.voters > 0
    );
  }

  get showRemoveVoteButton() {
    return (
      !this.showResults &&
      !this.closed &&
      !this.hideResultsDisabled &&
      this.hasSavedVote
    );
  }

  get isCheckbox() {
    if (this.isMultiple) {
      return true;
    } else {
      return false;
    }
  }

  get resultsWidgetTypeClass() {
    const type = this.poll.type;
    return this.isNumber || this.poll.chart_type !== PIE_CHART_TYPE
      ? `discourse-poll-${type}-results`
      : "discourse-poll-pie-chart";
  }

  get resultsPie() {
    return this.poll.chart_type === PIE_CHART_TYPE;
  }

  get averageRating() {
    const totalScore = this.options.reduce((total, o) => {
      return total + parseInt(o.html, 10) * parseInt(o.votes, 10);
    }, 0);
    const average = this.voters === 0 ? 0 : round(totalScore / this.voters, -2);

    return htmlSafe(I18n.t("poll.average_rating", { average }));
  }

  @action
  fetchVoters(optionId) {
    let votersCount;
    let preloadedVoters = this.preloadedVoters;

    Object.keys(preloadedVoters).forEach((key) => {
      if (key === optionId) {
        preloadedVoters[key].loading = true;
      }
    });

    this.preloadedVoters = Object.assign(preloadedVoters);

    votersCount = this.options.find((option) => option.id === optionId).votes;

    return ajax("/polls/voters.json", {
      data: {
        post_id: this.post.id,
        poll_name: this.poll.name,
        option_id: optionId,
        page: Math.floor(votersCount / FETCH_VOTERS_COUNT) + 1,
        limit: FETCH_VOTERS_COUNT,
      },
    })
      .then((result) => {
        const voters =
          (optionId
            ? this.preloadedVoters[optionId].voters
            : this.preloadedVoters) || [];

        const newVoters = optionId ? result.voters[optionId] : result.voters;
        if (this.isRankedChoice) {
          this.preloadedVoters[optionId] = [...new Set([...newVoters])];
        } else {
          const votersSet = new Set(voters.map((voter) => voter.username));
          newVoters.forEach((voter) => {
            if (!votersSet.has(voter.username)) {
              votersSet.add(voter.username);
              voters.push(voter);
            }
          });
          // remove users who changed their vote
          if (this.poll.type === REGULAR) {
            Object.keys(this.preloadedVoters).forEach((otherOptionId) => {
              if (optionId !== otherOptionId) {
                this.preloadedVoters[otherOptionId].voters =
                  this.preloadedVoters[otherOptionId].voters.filter(
                    (voter) => !votersSet.has(voter.username)
                  );
              }
            });
          }
        }
      })
      .catch((error) => {
        if (error) {
          popupAjaxError(error);
        } else {
          this.dialog.alert(I18n.t("poll.error_while_fetching_voters"));
        }
      })
      .finally(() => {
        preloadedVoters = this.preloadedVoters;
        preloadedVoters[optionId].loading = false;
        this.preloadedVoters = Object.assign(preloadedVoters);
      });
  }

  @action
  dropDownClick(dropDownAction) {
    this[dropDownAction]();
  }

  @action
  removeVote() {
    return ajax("/polls/vote", {
      type: "DELETE",
      data: {
        post_id: this.post.id,
        poll_name: this.poll.name,
      },
    })
      .then(({ poll }) => {
        if (this.poll.type === RANKED_CHOICE) {
          poll.options.forEach((option) => {
            option.rank = 0;
          });
        }
        this.vote = Object.assign([]);
        this.hasSavedVote = false;
        this.appEvents.trigger("poll:voted", poll, this.post, this.vote);
        this.showResults = false;
      })
      .catch((error) => {
        popupAjaxError(error);
      });
  }

  @action
  toggleStatus() {
    this.dialog.yesNoConfirm({
      message: I18n.t(this.closed ? "poll.open.confirm" : "poll.close.confirm"),
      didConfirm: () => {
        const status = this.closed ? "open" : "closed";
        ajax("/polls/toggle_status", {
          type: "PUT",
          data: {
            post_id: this.post.id,
            poll_name: this.poll.name,
            status,
          },
        })
          .then(() => {
            this.poll.status = status;
            this.status = status;
            this.closed = status === "closed";
            if (
              this.poll.results === "on_close" ||
              this.poll.results === "always"
            ) {
              this.showResults = status === "closed";
            }
          })
          .catch((error) => {
            if (error) {
              popupAjaxError(error);
            } else {
              this.dialog.alert(I18n.t("poll.error_while_toggling_status"));
            }
          });
      },
    });
  }

  @action
  showBreakdown() {
    this.modal.show(PollBreakdownModal, {
      model: this.args.attrs,
    });
  }

  @action
  exportResults() {
    const queryID =
      this.poll.type === RANKED_CHOICE
        ? this.siteSettings.poll_export_ranked_choice_data_explorer_query_id
        : this.siteSettings.poll_export_data_explorer_query_id;

    // This uses the Data Explorer plugin export as CSV route
    // There is detection to check if the plugin is enabled before showing the button
    ajax(`/admin/plugins/explorer/queries/${queryID}/run.csv`, {
      type: "POST",
      data: {
        // needed for data-explorer route compatibility
        params: JSON.stringify({
          poll_name: this.poll.name,
          post_id: this.post.id.toString(), // needed for data-explorer route compatibility
        }),
        explain: false,
        limit: 1000000,
        download: 1,
      },
    })
      .then((csvContent) => {
        const downloadLink = document.createElement("a");
        const blob = new Blob([csvContent], {
          type: "text/csv;charset=utf-8;",
        });
        downloadLink.href = URL.createObjectURL(blob);
        downloadLink.setAttribute(
          "download",
          `poll-export-${this.args.poll.name}-${this.args.post.id}.csv`
        );
        downloadLink.click();
        downloadLink.remove();
      })
      .catch((error) => {
        if (error) {
          popupAjaxError(error);
        } else {
          this.dialog.alert(I18n.t("poll.error_while_exporting_results"));
        }
      });
  }

  <template>
    <div class="poll-container">
      {{htmlSafe @titleHTML}}
      {{#if this.notInVotingGroup}}
        <div class="alert alert-danger">{{this.pollGroups}}</div>
      {{/if}}
      {{#if this.showResults}}
        <div class={{this.resultsWidgetTypeClass}}>
          {{#if @isNumber}}
            <span>{{this.averageRating}}</span>
          {{else}}
            {{#if this.resultsPie}}
              <PollResultsPie @id={{this.id}} @options={{this.options}} />
            {{else}}
              <PollResultsTabs
                @options={{this.options}}
                @pollName={{this.poll.name}}
                @pollType={{this.poll.type}}
                @isRankedChoice={{this.isRankedChoice}}
                @isPublic={{this.poll.public}}
                @postId={{this.post.id}}
                @vote={{this.vote}}
                @voters={{this.preloadedVoters}}
                @votersCount={{this.poll.voters}}
                @fetchVoters={{this.fetchVoters}}
                @rankedChoiceOutcome={{this.rankedChoiceOutcome}}
              />
            {{/if}}
          {{/if}}
        </div>
      {{else}}
        <PollOptions
          @isCheckbox={{this.isCheckbox}}
          @isRankedChoice={{this.isRankedChoice}}
          @rankedChoiceDropdownContent={{this.rankedChoiceDropdownContent}}
          @options={{this.options}}
          @votes={{this.vote}}
          @sendOptionSelect={{this.toggleOption}}
        />
      {{/if}}
    </div>
    <PollInfo
      @options={{this.options}}
      @min={{this.min}}
      @max={{this.max}}
      @isMultiple={{this.isMultiple}}
      @close={{this.close}}
      @closed={{this.closed}}
      @results={{this.poll.results}}
      @showResults={{this.showResults}}
      @postUserId={{this.poll.post.user_id}}
      @isPublic={{this.poll.public}}
      @hasVoted={{this.hasVoted}}
      @voters={{this.voters}}
    />
    <div class="poll-buttons">
      {{#if this.showCastVotesButton}}
        <DButton
          class={{this.castVotesButtonClass}}
          @title="poll.cast-votes.title"
          @disabled={{this.castVotesDisabled}}
          @action={{this.castVotes}}
          @icon={{this.castVotesButtonIcon}}
          @label="poll.cast-votes.label"
        />
      {{/if}}

      {{#if this.showHideResultsButton}}
        <DButton
          class="btn btn-default toggle-results"
          @title="poll.hide-results.title"
          @action={{this.toggleResults}}
          @icon="chevron-left"
          @label="poll.hide-results.label"
        />
      {{/if}}

      {{#if this.showShowResultsButton}}
        <DButton
          class="btn btn-default toggle-results"
          @title="poll.show-results.title"
          @action={{this.toggleResults}}
          @icon="chart-bar"
          @label="poll.show-results.label"
        />
      {{/if}}

      {{#if this.showRemoveVoteButton}}
        <DButton
          class="btn btn-default remove-vote"
          @title="poll.remove-vote.title"
          @action={{this.removeVote}}
          @icon="undo"
          @label="poll.remove-vote.label"
        />
      {{/if}}

      <PollButtonsDropdown
        @closed={{this.closed}}
        @voters={{this.voters}}
        @isStaff={{this.isStaff}}
        @isMe={{this.isMe}}
        @isRankedChoice={{this.isRankedChoice}}
        @topicArchived={{this.topicArchived}}
        @groupableUserFields={{this.groupableUserFields}}
        @isAutomaticallyClosed={{this.isAutomaticallyClosed}}
        @dropDownClick={{this.dropDownClick}}
      />
    </div>
  </template>
}
