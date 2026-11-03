# As in locke: UserMailer.with(user:).invitation_instructions
class UserMailer < ApplicationMailer
  def invitation_instructions
    @user = params[:user]
    mail to: @user.email, subject: "You're invited"
  end
end
