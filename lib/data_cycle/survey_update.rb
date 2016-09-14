# frozen_string_literal: true
require "#{Rails.root}/lib/data_cycle/batch_update_logging"
require "#{Rails.root}/lib/surveys/survey_notifications_manager"

class SurveyUpdate
  include BatchUpdateLogging

  def initialize
    @error_count = 0
    setup_logger
    log_start_of_update
    create_survey_notifications
    send_survey_notifications
    send_survey_notification_follow_ups
    log_end_of_update 'Survey update finished.'
  end

  private

  def create_survey_notifications
    log_message 'Creating new SurveyNotifications'
    before_count = SurveyNotification.count
    SurveyNotificationsManager.create_notifications
    after_count = SurveyNotification.count
    log_message "#{after_count - before_count} SurveyNotifications created"
  end

  def send_survey_notifications
    log_message 'Sending survey invitation emails'
    before_count = SurveyNotification.where.not(email_sent_at: nil).count
    try_to_process_notifications(:send_email)
    after_count = SurveyNotification.where.not(email_sent_at: nil).count
    log_message "#{after_count - before_count} survey invitations sent"
  end

  def send_survey_notification_follow_ups
    log_message 'Sending survey reminder emails'
    before_count = SurveyNotification.sum(:follow_up_count)
    try_to_process_notifications(:send_follow_up)
    after_count = SurveyNotification.sum(:follow_up_count)
    log_message "#{after_count - before_count} survey reminders sent"
  end

  def log_start_of_update
    @start_time = Time.zone.now
  end

  def try_to_process_notifications(method)
    SurveyNotification.active.each do |notification|
      notification.send(method)
      # Don't send emails too quickly, to avoid being throttled by gmail
      sleep 2 unless Rails.env == 'test'
    end
  rescue Net::SMTPAuthenticationError => e
    log_message "SMTP authentication error #{@error_count += 1}"
    sleep 10 unless Rails.env == 'test'
    retry unless @error_count >= 3
    log_end_of_update 'Survey update errored'
    raise e
  end
end
