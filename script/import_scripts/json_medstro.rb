# frozen_string_literal: true

require "csv"
require File.expand_path(File.dirname(__FILE__) + "/base.rb")

# Edit the constants and initialize method for your import data.

class ImportScripts::JsonGeneric < ImportScripts::Base

  JSON_FILE_PATH = ENV['JSON_FILE']
  JSON_USER_FILE = 'users.json'
  JSON_USER_EXTRAS_FILE = 'users_additional_info.json'
  USER_AVATAR_DIRECTORY = 'user_avatars/'
  JSON_FILE_DIRECTORY = '/shared/import/data/ama-pin-transfer/'
  BATCH_SIZE ||= 1000

  def initialize
    super

    @imported_user_json = load_user_json
  end

  def execute
    puts "", "Importing from JSON file..."

    import_users
    # import_discussions

    puts "", "Done"
  end

  def load_user_json
    master = JSON.parse(File.read(JSON_FILE_DIRECTORY + JSON_USER_FILE))
    additional = JSON.parse(File.read(JSON_FILE_DIRECTORY + JSON_USER_EXTRAS_FILE))
    
    mrg = []
    master.each do |master_record|
      additional.each do |additional_record|
        if additional_record['user_id'] == master_record['id']
          mrg.push(master_record.merge(additional_record))
        end
      end
    end
    mrg
  end

  def username_for(name)
    result = name.downcase.gsub(/[^a-z0-9\-\_]/, '')

    if result.blank?
      result = Digest::SHA1.hexdigest(name)[0...10]
    end

    result
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

if __FILE__ == $0
  ImportScripts::JsonGeneric.new.perform
end
