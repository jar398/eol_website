class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :confirmable,
         :omniauthable, omniauth_providers: [:facebook, :twitter,
                                             :google_oauth2, :yahoo]

  has_many :open_authentications, dependent: :delete_all
  has_many :curations, inverse_of: :user
  has_many :trait_curations, inverse_of: :user
  has_many :added_associations, class_name: "PageContent", foreign_key: "association_added_by_user_id"

  has_and_belongs_to_many :partners
  has_and_belongs_to_many :collections
  # TODO: this wasn't working, not sure why.
#   has_and_belongs_to_many :managed_collections,
#     class_name: "Collection",
#     association_foreign_key: "collection_id",
#     -> { where(is_manager: true) }

  validates :username, presence: true, length: { minimum: 4, maximum: 32 }

  USERNAME_MIN_LENGTH = 4
  USERNAME_MAX_LENGTH = 32
  DUMMY_EMAIL_FOR_DELETE = "dummy@eol.org"

  # NOTE: this is a hook called by Devise
  def after_confirmation
    activate
  end

  def activate
    self.update_attributes(active: true)
  end

  def soft_delete
    self.skip_reconfirmation!
    self.update_attributes!(deleted_at: Time.current, email: DUMMY_EMAIL_FOR_DELETE,
      encrypted_password: nil, active: false)
  end

  # def email_required?
    # false
  # end

  # TODO: switch this to a role (once we have roles)
  def is_admin?
    admin?
  end

  def can_delete_account? (user)
    self.is_admin? || self == user
  end
end
