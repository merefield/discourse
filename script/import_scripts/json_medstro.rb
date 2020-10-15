# frozen_string_literal: true

require "csv"
require File.expand_path(File.dirname(__FILE__) + "/base.rb")

# Edit the constants and initialize method for your import data.

class ImportScripts::JsonGeneric < ImportScripts::Base

  JSON_FILE_PATH = ENV['JSON_FILE']
  JSON_USER_FILE = 'users.json'
  JSON_GROUP_FILE = 'groups.json'
  JSON_DISCUSSION_FILE = 'discussions.json'
  JSON_USER_EXTRAS_FILE = 'users_additional_info.json'
  USER_AVATAR_DIRECTORY = 'user_avatars/'
  GROUP_AVATAR_DIRECTORY = 'group_avatars/'
  JSON_FILE_DIRECTORY = '/shared/import/data/ama-pin-transfer/'
  BATCH_SIZE ||= 1000

  def initialize
    super
    puts "", "Reset data..."
    reset_instance
    puts "", "Importing from JSON files..."
    puts "", "Importing User JSON ..."
    @imported_user_json = load_user_json
    puts "", "Importing Group JSON ..."
    @imported_group_json = load_group_json
    puts "", "Importing Discussion JSON ..."
    @imported_discussion_json = load_discussion_json
  end

  def reset_instance
    puts "", "Scrubbing..."
    puts "", "Scrubbing Categories..."
    Category.where("id > 4").destroy_all
    puts "", "Scrubbing Users..."
    User.where("id > 1").destroy_all
    puts "", "Scrubbing Groups..."
    Group.where("automatic = FALSE").destroy_all
  end

  def execute
    puts "", "Executing import..."

    import_groups
    import_users
    import_categories
    #import_topics
    #import_posts
    #add_moderators
    #add_admins
    #import_avatars
    #create_permalinks

    puts "", "Done"
  end

  def load_user_json
    master = JSON.parse(File.read(JSON_FILE_DIRECTORY + JSON_USER_FILE))
    additional = JSON.parse(File.read(JSON_FILE_DIRECTORY + JSON_USER_EXTRAS_FILE))
    
    mrg = []
    master.first(50).each do |master_record|
      additional.each do |additional_record|
        if additional_record['user_id'] == master_record['id']
          mrg.push(master_record.merge(additional_record))
        end
      end
    end
    mrg
  end

  def load_group_json
    master = JSON.parse(File.read(JSON_FILE_DIRECTORY + JSON_GROUP_FILE))

    subset = []
    top_level = []
    master.each do |master_record|
      if master_record['parent_group_id'] == 203 #|| master_record['id'] == 203
        top_level.push(master_record)
      end
    end

    master.each do |master_record|
      top_level.each do |top_level|
        if master_record['parent_group_id'] == top_level['id'] #|| master_record['id'] == 203
          subset.push(master_record)
        end
      end
    end

    top_level.each do |top_level|
      subset.push(top_level)
    end

    puts subset

    subset
  end

  def load_discussion_json
    JSON.parse(File.read(JSON_FILE_DIRECTORY + JSON_DISCUSSION_FILE))
  end

  def username_for(name)
    result = name.downcase.gsub(/[^a-z0-9\-\_]/, '')

    if result.blank?
      result = Digest::SHA1.hexdigest(name)[0...10]
    end

    result
  end

  def import_groups
    puts '', "Importing groups"

    groups = []

    @imported_group_json.each do |g|
      if g['parent_group_id'] == 203
        groups << g
      end
    end

    groups.uniq!

    puts groups[0]

    create_groups(groups) do |g|
      {
        id: g['id'],
        name: g['name'],
        full_name: g['name'],
        bio_raw: g['description'],
        visibility_level: g['private'] ? 3 : 1,
        members_visibility_level: g['private'] ? 3 : 1,
        created_at: Time.now, #g['joined'],
        updated_at: Time.now,
        post_create_action: proc do |newgroup|
          puts newgroup.id.to_s
          puts g['id'].to_s
          newgroup.custom_fields["import_parent_group_id"] = g['parent_group_id']
          png_path = JSON_FILE_DIRECTORY + GROUP_AVATAR_DIRECTORY + g['id'].to_s + '.png'
          if File.exists?(png_path)
            upload = create_upload(newgroup.id, png_path, File.basename(png_path))
            puts upload.to_s
            if upload.nil?
              puts "Upload failed. Path #{png_path} Id New #{newgroup.id}"
            else
              puts "Upload succeeded. Path #{png_path} Id New #{newgroup.id}  Upload Id #{upload.id} "
              newgroup.update(flair_upload_id: upload.id)
            end
          end
        end
      }
    end
  end

  def import_users
    puts '', "Importing users"

    users = []


    @imported_user_json.each do |u|
      users << u
    end
    users.uniq!

    puts users[0]

    create_users(users.first(15)) do |u|
      {
        id: u['id'],
        username: u['shortname'],
        name: (u['title'] + ' ' + u['firstname'] + ' ' + u['middlename'] + ' ' + u['lastname'] + ' ' + u['suffix']).gsub(/ +/, " "),
        email: u['email'],
        location: (u['address_first_line'] + ' ' + u['postal_code'] + ' ' + u['city'] + + ' ' + u['state'] + ' ' + u['country']).gsub(/ +/, " "),
        website: u['url'].presence || u['linkedin'].presence || u['googleplus'].presence || u['twitter'].presence || u['facebook'].presence || u['tumblr'].presence  || u['pinterest'].presence,
        bio_raw: u['summary'],
        date_of_birth: u['birth_day'].to_s + '/' + u['birth_month'].to_s + '/' +  u['birth_year'].to_s,
        created_at: u['joined'],
        updated_at: Time.now,
        post_create_action: proc do |newuser|
          add_user_to_groups(newuser, u['group_ids'])

          puts newuser.id.to_s
          puts u['id'].to_s
          png_path = JSON_FILE_DIRECTORY + USER_AVATAR_DIRECTORY + u['id'].to_s + '.png'
          jpg_path = JSON_FILE_DIRECTORY + USER_AVATAR_DIRECTORY + u['id'].to_s + '.jpg'
          if File.exists?(png_path)
            upload = create_upload(newuser.id, png_path, File.basename(png_path))
            puts upload.to_s
            if upload.nil?
              puts "Upload failed. Path #{png_path} Id New #{newuser.id}"
            else
              puts "Upload succeeded. Path #{png_path} Id New #{newuser.id}  Upload Id #{upload.id} "
              newuser.create_user_avatar
              newuser.user_avatar.update(custom_upload_id: upload.id)
              newuser.update(uploaded_avatar_id: upload.id)
            end
          elsif File.exists?(jpg_path)
            upload = create_upload(newuser.id, jpg_path, File.basename(jpg_path))
            puts upload.to_s
            if upload.nil?
              puts "Upload failed. Path #{jpg_path} Id New #{newuser.id}"
            else
              puts "Upload succeeded. Path #{jpg_path} Id New #{newuser.id}  Upload Id #{upload.id} "
              newuser.create_user_avatar
              newuser.user_avatar.update(custom_upload_id: upload.id)
              newuser.update(uploaded_avatar_id: upload.id)
            end
          end
        end
      }
    end
  end

  def import_categories
    puts "", "Importing Categories"

    top_level_categories = []
    mid_level_categories = []
    child_categories = []
    eligible = []

    # Group.all.each do |group|
    #   if group.automatic == false
    #     eligible.push(group.custom_fields["import_id"])
    #   end
    # end

    puts "", "Importing Top Level Categories"

    @imported_group_json.each do |top_level_category|
      if top_level_category['parent_group_id'] == 203
        top_level_categories.push(top_level_category)
        eligible.push(top_level_category['id'])
      end
    end

    top_level_categories.uniq!

    puts top_level_categories[0]

    puts "", "Found #{top_level_categories.count} Top Level Categories"
    puts "", "Found #{eligible.count} Eligible Parent Categories so far"

    Category.transaction do
      create_categories(top_level_categories) do |g|
        {
          id: g['id'],
          name: g['name'],
          description: g['description'],
          created_at: Time.now,
          updated_at: Time.now,
          post_create_action: proc do |newcategory|
            newcategory.custom_fields["import_group_id"] = g['id'].to_s
            newcategory.save!
          end
        }
      end
    end

    @imported_group_json.each do |mid_level_category|
      if mid_level_category['parent_group_id'] != 203
        mid_level_categories.push(mid_level_category)
        eligible.push(mid_level_category['id'])
      end
    end

    mid_level_categories.uniq!

    puts mid_level_categories[0]

    puts "", "Found #{mid_level_categories.count} Mid Level Categories"
    puts "", "Found #{eligible.count} Eligible Parent Categories so far"


    Category.transaction do
      create_categories(mid_level_categories) do |g|
        {
          id: g['id'],
          name: g['name'],
          description: g['description'],
          created_at: Time.now,
          updated_at: Time.now,
          post_create_action: proc do |newcategory|
            newcategory.custom_fields["import_group_id"] = g['id'].to_s
            newcategory.custom_fields["import_parent_group_id"] = g['parent_group_id'].to_s
            newcategory.save!
          end
        }
      end
    end

    puts "", "Importing Child Categories"

    @imported_discussion_json.each do |child_category|
      if eligible.include?(child_category['group_id'].to_s)
        # Group.all.each do |g|
        #   if g.custom_fields["import_id"] == category['parent_group_id'].to_s
            #byebug
            #category['import_parent_group_id'] = g.custom_fields["import_parent_group_id"]
        child_categories.push(child_category)
            # break
          # end
        # end
      end
    end
    
    child_categories.uniq!

    puts child_categories[0]

    puts "", "Found #{child_categories.count} Child Level Categories"

    Category.transaction do
      create_categories(child_categories) do |c|
        {
          id: c['id'],
          name: c['title'],
          description: c['description'],
          created_at: Time.now,
          updated_at: Time.now,
          post_create_action: proc do |newcategory|
            newcategory.custom_fields["import_parent_group_id"] = c['import_parent_group_id'].to_s
            newcategory.custom_fields["import_group_id"] = c['group_id'].to_s
            newcategory.save!
          end
        }
      end
    end

    Category.transaction do
      Category.all.each do |category|
        if category.custom_fields["import_parent_group_id"]
          Category.all.each do |potential_parent_category|
            if potential_parent_category.custom_fields["import_group_id"] == category.custom_fields["import_parent_group_id"]
              byebug
              category.parent_category_id = potential_parent_category.id
            end
          end
        end
      end
    end
  end

  def import_discussions
    puts "", "Importing discussions"

    topics = 0
    posts = 0

    @imported_json['topics'].each do |t|
      first_post = t['posts'][0]
      next unless first_post

      topic = {
        id: t["id"],
        user_id: user_id_from_imported_user_id(username_for(first_post["author"])) || -1,
        raw: first_post["body"],
        created_at: Time.zone.parse(first_post["date"]),
        cook_method: Post.cook_methods[:raw_html],
        title: t['title'],
        category: ENV['CATEGORY_ID'],
        custom_fields: { import_id: "pid:#{first_post['id']}" }
      }

      topic[:pinned_at] = Time.zone.parse(first_post["date"]) if t['pinned']
      topics += 1
      parent_post = create_post(topic, topic[:id])

      t['posts'][1..-1].each do |p|
        create_post({
          id: p["id"],
          topic_id: parent_post.topic_id,
          user_id: user_id_from_imported_user_id(username_for(p["author"])) || -1,
          raw: p["body"],
          created_at: Time.zone.parse(p["date"]),
          cook_method: Post.cook_methods[:raw_html],
          custom_fields: { import_id: "pid:#{p['id']}" }
        }, p['id'])
        posts += 1
      end
    end

    puts "", "Imported #{topics} topics with #{topics + posts} posts."
  end
end

def add_user_to_groups(user, imported_groups)
  puts "", "adding user #{user.id} to groups..."

  GroupUser.transaction do
    GroupUser.where("user_id = #{user.id}").each do |group_user|
      if !Group.find_by(id: group_user.group_id).automatic
        group_user.delete
      end
    end
    imported_groups.each do |mgid|
      (group_id = group_id_from_imported_group_id(mgid)) &&
        GroupUser.find_or_create_by(user: user, group_id: group_id) &&
      Group.reset_counters(group_id, :group_users)
    end
  end
end

if __FILE__ == $0
  ImportScripts::JsonGeneric.new.perform
end
