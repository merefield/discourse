# frozen_string_literal: true

require "csv"
require File.expand_path(File.dirname(__FILE__) + "/base.rb")

# Edit the constants and initialize method for your import data.

class ImportScripts::JsonGeneric < ImportScripts::Base

  JSON_FILE_PATH = ENV['JSON_FILE']
  JSON_USER_FILE = 'users.json'
  JSON_GROUP_FILE = 'groups.json'
  JSON_TOPIC_FILE = 'posts.json'
  JSON_POST_FILE = 'comments.json'
  JSON_DISCUSSION_FILE = 'discussions.json'
  JSON_USER_EXTRAS_FILE = 'users_additional_info.json'
  USER_AVATAR_DIRECTORY = 'user_avatars/'
  GROUP_AVATAR_DIRECTORY = 'group_avatars/'
  CATEGORY_LOGO_DIRECTORY = 'group_avatars/'
  CATEGORY_BACKGROUND_DIRECTORY = 'group_banners/'
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
    puts "", "Importing Topics JSON ..."
    @imported_topic_json = load_topic_json
    puts "", "Importing Posts JSON ..."
    @imported_post_json = load_post_json

  end

  def reset_instance
    puts "", "Scrubbing..."
    puts "", "Scrubbing Categories..."
    Category.where("id > 4").destroy_all
    puts "", "Scrubbing Users..."
    User.where("id > 1").destroy_all
    puts "", "Scrubbing Groups..."
    Group.where("automatic = FALSE").destroy_all
    puts "", "Scrubbing Topics..."
    Topic.destroy_all
    Post.destroy_all
  end

  def execute
    puts "", "Executing import..."

    import_groups
    import_users
    import_categories
    import_topics
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
    master.first(100).each do |master_record|
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

    top_level.each do |top_level|
      subset.push(top_level)
    end

    master.each do |master_record|
      top_level.each do |top_level|
        if master_record['parent_group_id'] == top_level['id'] #|| master_record['id'] == 203
          subset.push(master_record)
        end
      end
    end

    puts subset

    subset
  end

  def load_discussion_json
    JSON.parse(File.read(JSON_FILE_DIRECTORY + JSON_DISCUSSION_FILE))
  end

  def load_topic_json
    JSON.parse(File.read(JSON_FILE_DIRECTORY + JSON_TOPIC_FILE))
  end

  def load_post_json
    JSON.parse(File.read(JSON_FILE_DIRECTORY + JSON_POST_FILE))
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

    create_users(users.first(20)) do |u|
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
          upload_avatar(newuser,u['id'])
          puts newuser.id.to_s
          puts u['id'].to_s
        end
      }
    end
  end

  def upload_avatar (newuser,import_user_id)
    base_path = JSON_FILE_DIRECTORY + USER_AVATAR_DIRECTORY + import_user_id.to_s
    png_path = base_path + '.png'
    jpg_path = base_path + '.jpg'
    upload = nil
    possible_paths = [png_path, jpg_path]
    possible_paths.each do |path|
      if File.exists?(path)
        upload = create_upload(newuser.id, path, File.basename(path))
        puts upload.to_s
        if upload.nil?
          puts "Upload failed. Path #{path} Id New #{newuser.id}"
        else
          puts "Upload succeeded. Path #{path} Id New #{newuser.id}  Upload Id #{upload.id} "
        end
        break
      end
    end
    if !upload.nil?
      newuser.update(uploaded_avatar_id: upload.id)
      puts "Avatar created for User #{newuser.id}  Upload Id #{upload.id} "
    else
      puts "No Avatar found for User #{newuser.id}"
    end
  end

  def import_categories
    puts "", "Importing Categories"

    categories = []
    leaf_categories = []
    eligible = []

    puts "", "Importing Categories"

    @imported_group_json.each do |category|
      category['is_discussion'] = false
      categories.push(category)
      eligible.push(category['id'])
    end

    puts "", "Found #{eligible.count} Eligible Parent Categories so far"

    @imported_discussion_json.each do |child_category|
      if eligible.include?(child_category['group_id'])
        child = Hash.new
        child['id'] = child_category['id']
        child['is_discussion'] = true
        child['parent_group_id'] = child_category['group_id']
        child['name'] =  child_category['title']
        child['description'] = child_category['description']
        categories.push(child)
        leaf_categories.push(child)
      end
    end

    puts "", "Found #{leaf_categories.count} Leaf Categories"

    categories.uniq!

    puts "", "Found #{categories.count} Categories"

    create_categories(categories) do |gd|
      h = {
        id: gd['is_discussion'] ? gd['id'] + 1000: gd['id'],
        name: gd['name'],
        description: gd['description'],
        created_at: Time.now,
        updated_at: Time.now,
        post_create_action: proc do |newcategory|
          upload_category_logo(newcategory,gd['id'])
          upload_category_background(newcategory,gd['id'])
          newcategory.custom_fields["import_group_id"] = gd['id'].to_s
          newcategory.custom_fields["import_parent_group_id"] = gd['parent_group_id'].to_s
          newcategory.save!
        end
      }
      if gd['parent_group_id'].to_i > 0 && gd['parent_group_id'].to_i != 203
        h[:parent_category_id] = category_id_from_imported_category_id(gd['parent_group_id'])
      end
      h
    end
  end

  def upload_category_logo (newcategory,import_group_id)
    base_path = JSON_FILE_DIRECTORY + CATEGORY_LOGO_DIRECTORY + import_group_id.to_s
    path = base_path + '.png'
    upload = nil

    if File.exists?(path)
      upload = create_upload(newcategory.id, path, File.basename(path))
      puts upload.to_s
      if upload.nil?
        puts "Upload failed. Path #{path} Id New #{newcategory.id}"
      else
        puts "Upload succeeded. Path #{path} Id New #{newcategory.id}  Upload Id #{upload.id} "
      end
    end

    if !upload.nil?
      newcategory.update(uploaded_logo_id: upload.id)
      puts "Logo created for Category #{newcategory.id}  Upload Id #{newcategory.id} "
    else
      puts "No logo found for Category #{newcategory.id}"
    end
  end

  def upload_category_background (newcategory,import_group_id)
    base_path = JSON_FILE_DIRECTORY + CATEGORY_BACKGROUND_DIRECTORY + import_group_id.to_s
    path = base_path + '.jpg'
    upload = nil

    if File.exists?(path)
      upload = create_upload(newcategory.id, path, File.basename(path))
      puts upload.to_s
      if upload.nil?
        puts "Upload failed. Path #{path} Id New #{newcategory.id}"
      else
        puts "Upload succeeded. Path #{path} Id New #{newcategory.id}  Upload Id #{upload.id} "
      end
    end

    if !upload.nil?
      newcategory.update(uploaded_background_id: upload.id)
      puts "Background created for Category #{newcategory.id}  Upload Id #{upload.id} "
    else
      puts "No Background found for Category #{newcategory.id}"
    end
  end

  def import_topics
    puts "", "Importing discussions"

    topics = 0
    posts = 0

    @imported_topic_json.first(100).each do |t|
      #first_post = t['posts'][0]
      #next unless first_post

      topic = {
        id: t['id'],
        is_op: true,
        user_id: user_id_from_imported_user_id(t['user_id']) || -1,
        raw: t['body'],
        created_at: t['created'],
        updated_at: t['updated'],
        cook_method: Post.cook_methods[:raw_html],
        title: t['title'],
        category: category_id_from_imported_category_id(t['group_id'] || (t['discussion_id'] + 1000)),
        custom_fields: { import_id: t['id'] }
      }

      #topic[:pinned_at] = Time.zone.parse(first_post["date"]) if t['pinned']
      topics += 1
      posts += 1
      parent_post = create_post(topic, topic[:id])
      add_topic(t['id'], parent_post) if parent_post

      if !t['attached_image_id'].blank?
        attach_media_to_post(parent_post, t['id'], 'post', 'attached_images', t['attached_image_id'])
      end
      if !t['media_upload_id'].blank?
        attach_media_to_post(parent_post, t['id'], 'post', 'media_uploads', t['media_upload_id'])
      end
    end

    @imported_post_json.first(300).each do |p|
      new_post = create_post({
        id: p['id'],
        is_op: false,
        topic_id: topic_id_from_imported_topic_id(p["post_id"]),
        user_id: user_id_from_imported_user_id((p["user_id"])) || -1,
        title: p['title'],
        raw: p['body'],
        created_at: p['created'],
        updated_at: p['updated'],
        cook_method: Post.cook_methods[:raw_html],
        custom_fields: { import_topic_id: p['post_id'], import_id: p['id'] }
      }, p['id'])
      posts += 1
      if !p['attached_image_id'].blank? && new_post
        attach_media_to_post(new_post, p['id'], 'comment', 'attached_images', p['attached_image_id'])
      end
      if !p['media_upload_id'].blank? && new_post
        attach_media_to_post(new_post, p['id'], 'comment', 'media_uploads', p['media_upload_id'])
      end
    end

    puts "", "Imported #{topics} topics with #{topics + posts} posts."
  end

  def add_user_to_groups(user, imported_groups)
    puts "", "adding user #{user.id} to groups..."

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

  def attach_media_to_post(post, import_post_id, level, type, media_id)
    base_path = JSON_FILE_DIRECTORY + level + '_' + type + '/' + media_id.to_s
    png_path = base_path + '.png'
    jpg_path = base_path + '.jpg'
    pdf_path = base_path + '.pdf'
    ppt_path = base_path + '.ppt'
    pptx_path = base_path + '.pptx'
    doc_path = base_path + '.doc'
    docx_path = base_path + '.docx'
    xls_path = base_path + '.xls'
    xlsx_path = base_path + '.xlsx'
    mp4_path = base_path + '.mp4'

    upload = nil
    possible_paths =
    [png_path,jpg_path, pdf_path,
      ppt_path, pptx_path, doc_path, docx_path, xls_path,
      xlsx_path, mp4_path, base_path]
    possible_paths.each do |path|
      if File.exists?(path)
        upload = create_upload(post.user.id || -1, path, File.basename(path))
        puts upload.to_s
        if !upload&.persisted?
          puts "Upload failed. Path #{path} For User Id #{post.user.id}"
        else
          html = html_for_upload(upload, File.basename(path))
          if !post.raw[html]
            post.raw << "\n\n" << html
            post.cook_method = 1
            post.save!
            PostUpload.create!(post: post, upload: upload) unless PostUpload.where(post: post, upload: upload).exists?
          end
          puts "Post upload succeeded. Path #{path} for User Id #{post.user.id || -1}  Upload Id #{upload.id} "
        end
        break
      end
    end
  end
end

if __FILE__ == $0
  ImportScripts::JsonGeneric.new.perform
end
