# frozen_string_literal: true

RSpec.describe UserPasswordExpirer do
  fab!(:password) { "somerandompassword" }
  fab!(:user) { Fabricate(:user, password:) }

  describe ".expire_user_password" do
    it "should create a new UserPassword record with the user's current password information" do
      freeze_time

      described_class.expire_user_password(user)

      expect(user.passwords.count).to eq(1)

      user_password = user.passwords.first

      expect(user_password.password_hash).to eq(user.password_hash)
      expect(user_password.password_salt).to eq(user.salt)
      expect(user_password.password_algorithm).to eq(user.password_algorithm)
      expect(user_password.password_expired_at).to eq_time(Time.zone.now)
    end
  end
end
