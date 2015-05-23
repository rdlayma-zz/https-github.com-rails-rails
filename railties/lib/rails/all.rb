require "rails"

%w(
  active_record
  action_controller
  action_mailer
  rails/test_unit
).each do |framework|
  begin
    require "#{framework}/railtie"
  rescue LoadError
  end
end
