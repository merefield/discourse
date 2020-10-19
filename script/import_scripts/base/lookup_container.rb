# frozen_string_literal: true

module ImportScripts
  class LookupContainer
    def initialize
      puts "", "Resetting import maps"
      @groups = {}
      @users = {}
      @categories = {}
      @posts = {}
      @topics = {}
    end

    # Get the Discourse Post id based on the id of the source record
    def post_id_from_imported_post_id(import_id)
      @posts[import_id] || @posts[import_id.to_s]
    end

    def topic_id_from_imported_topic_id(import_id)
      @topics[import_id] || @topics[import_id.to_s]
    end

    # Get the Discourse topic info (a hash) based on the id of the source record
    def topic_lookup_from_imported_post_id(import_id)
      post_id = post_id_from_imported_post_id(import_id)
      post_id ? @topics[post_id] : nil
    end

    # Get the Discourse Group id based on the id of the source group
    def group_id_from_imported_group_id(import_id)
      @groups[import_id] || @groups[import_id.to_s]
    end

    # Get the Discourse Group based on the id of the source group
    def find_group_by_import_id(import_id)
      GroupCustomField.where(name: 'import_id', value: import_id.to_s).first.try(:group)
    end

    # Get the Discourse User id based on the id of the source user
    def user_id_from_imported_user_id(import_id)
      @users[import_id] || @users[import_id.to_s]
    end

    # Get the Discourse User based on the id of the source user
    def find_user_by_import_id(import_id)
      UserCustomField.where(name: 'import_id', value: import_id.to_s).first.try(:user)
    end

    # Get the Discourse Category id based on the id of the source category
    def category_id_from_imported_category_id(import_id)
      @categories[import_id] || @categories[import_id.to_s]
    end

    def add_group(import_id, group)
      @groups[import_id.to_s] = group.id
    end

    def add_user(import_id, user)
      @users[import_id.to_s] = user.id
    end

    def add_category(import_id, category)
      @categories[import_id.to_s] = category.id
    end

    def add_post(import_id, post)
      @posts[import_id.to_s] = post.id
    end

    def add_topic(import_id, post)
      @topics[import_id.to_s] = post.topic_id
    end

    def user_already_imported?(import_id)
      @users.has_key?(import_id) || @users.has_key?(import_id.to_s)
    end

    def post_already_imported?(import_id)
      @posts.has_key?(import_id) || @posts.has_key?(import_id.to_s)
    end

  end
end
