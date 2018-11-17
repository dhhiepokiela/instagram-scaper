require 'selenium-webdriver'
require 'chromedriver-helper'
require 'rubygems'
# require 'pry'
# require 'sendgrid-ruby'
require 'base64'
require 'fileutils'
# require 'dotenv/load'
require 'redis'

class Instagram
  # include SendGrid

  @@driver = nil
  @@redis = nil

  def self.current_session
    return @@driver if @@driver
    @@driver = create_selenium_session
  end

  def self.clear_all_cookies
    redis_store('previous_cookies', nil)
  end

  def self.store_all_cookies
    redis_store('previous_cookies', current_session.manage.all_cookies.to_json)
  end

  def self.restore_all_cookies
    return false unless redis_load('previous_cookies').is_a?(Array)
    redis_load('previous_cookies').each do |cookie|
      cookie[:expires] = Time.parse(cookie[:expires]) if cookie[:expires]
      current_session.manage.add_cookie(cookie)
    end
  end

  def self.create_selenium_session
    puts "Creating browser for #{ENV['SELENIUM_TYPE'] || 'destop'}"

    default_capabilities = {
      args: %w(start-maximized disable-infobars disable-extensions)
      # args: %w(start-maximized disable-infobars disable-extensions)
    }
    
    default_capabilities.merge!(binary: ENV['GOOGLE_CHROME_SHIM']) if ENV.fetch('GOOGLE_CHROME_SHIM', nil)

    capabilities = Selenium::WebDriver::Remote::Capabilities.chrome(chromeOptions: default_capabilities)

    case ENV['SELENIUM_TYPE']
    when 'heroku'
      Selenium::WebDriver.for :chrome, desired_capabilities: capabilities # for heroku 
    when 'ubuntu'
      Selenium::WebDriver.for :remote, url: "http://127.0.0.1:9515", desired_capabilities: capabilities
    else
      Selenium::WebDriver.for :chrome, desired_capabilities: capabilities # for destop
    end 
  end

  def self.get_images(phone)
    # data = redis_load(phone)

    # if data
    #   puts "Load data from cache instead of from Instagram server for #{phone}"
    #   return data
    # end
    current_session.navigate.to 'https://www.instagram.com/jinmiran_'

    binding.pry


    imgs = current_session.find_elements(css: 'img[decoding=auto]') rescue nil
    if imgs && imgs.any?
    end

    search_field = current_session.find_element(css: '[data-translate-placeholder="STR_INPUT_PHONE_NUMBER"]') rescue nil
    search_field.send_key(phone) if search_field

    # Click btn find
    current_session.find_element(css: '[data-translate-inner="STR_FIND_FRIEND"]').click  rescue nil
    sleep(0.5)

    username = current_session.find_element(class: 'usname').text rescue nil

    owner_info =
      if username
        gender = current_session.find_element(css: '[data-translate-inner="STR_GENDER_MALE"]') rescue nil
        gender = gender ? 'Nam' : 'Nữ'

        
        avatar = current_session.find_element(css: '.avatar.avatar--profile.clickable .avatar-img.outline') rescue nil
        avatar = avatar.css_value('background-image').scan(/https:\/\/.*\"/).first.gsub("\"", '') rescue ''

        birth_day = current_session.find_element(css: '[data-translate-inner="STR_PROFILE_LABEL_BIRTHDAY"]') rescue nil
        birth_day = birth_day.find_element(xpath: '..').find_element(css: 'span:last-child').text rescue nil

        clear_search_fields
        
        redis_store(phone, { avatar: avatar, phone: phone, name: username, gender: gender, birth_day: birth_day}.to_json)
      else
        redis_store(phone, { avatar: 'https://www.gravatar.com/avatar/xxx.jpg', phone: phone, name: 'Unknown', gender: 'Unknown', birth_day: 'Unknown'}.to_json)
      end

    owner_info
  end

  def self.login
    3.times do |i|
      begin
        restore_all_cookies
        current_session.navigate.to 'https://chat.instagram.me/'
      rescue Exception => e
        @@driver = nil
        current_session
        sleep(0.5)
        restore_all_cookies
        current_session.navigate.to 'https://chat.instagram.me/'
      end

      sleep(0.5)
      invite_btn = current_session.find_element(id: 'inviteBtn') rescue nil
      return invite_btn.click if invite_btn # Previous cookies worked 
    end

    # Change to QR tab
    current_session.find_element(css: '.body-container > div > .tabs > ul > li:last-child a').click rescue nil

    capture_qr_code_and_send_email

    until (current_session.find_element(id: 'inviteBtn') rescue nil)
      puts 'Waiting for account loged in to click button Find friends'
      sleep(0.5)
      qr_expired = current_session.find_element(css: '.qrcode-expired') rescue nil
      if qr_expired && qr_expired.css_value('display') == 'block'
        qr_expired.click if qr_expired
        capture_qr_code_and_send_email
        puts 'Reload QR Code'
      end
    end

    store_all_cookies
  end

  def self.clear_search_fields
    # Clear
    current_session.find_element(css: '.btn.clearBtn.flx-fix.fa.fa-clear').click rescue ''    

    # fill phone number
    search_field = current_session.find_element(css: '[data-translate-placeholder="STR_INPUT_PHONE_NUMBER"]') rescue nil
    20.times { search_field.send_key(Selenium::WebDriver::Keys::KEYS[:backspace]) } if search_field
  end

  def self.capture_qr_code_and_send_email
    # Save screenshot QR code and send to email
    qr_name = "qr_code_#{Time.now.to_i}.png"
    file_path = File.join(@@folder_path, qr_name)
    current_session.manage.window.resize_to(350, 600)
    sleep(0.5)
    current_session.save_screenshot(file_path)
    current_session.manage.window.resize_to(1400, 700)
    send_email_qr_code(file_path).to_json
  end

  def self.prepare_instagram_search_from
    login # login follow

    until (current_session.find_element(css: '.modal.animated.fadeIn.appear') rescue nil)
      puts 'Waiting for modal search contact display'
      current_session.find_element(id: 'inviteBtn').click rescue nil
      sleep(0.5)
    end
  end

  def self.send_email_qr_code(file_path)
    puts 'Sending email with QR code ...'
    from = SendGrid::Email.new(email: 'instagram_qr_code@hiepdinh.info')
    to = SendGrid::Email.new(email: ENV['EMAIL_RECEIVE_QR_CODE'])
    subject = 'Instagram QR Code Login'
    content = SendGrid::Content.new(type: 'text/plain', value: 'Using Instagram App scan this QR code to login your account')
    mail = SendGrid::Mail.new(from, subject, to, content)

    attachment = Attachment.new
    attachment.content = Base64.strict_encode64(open(file_path).to_a.join)
    attachment.type = 'image/png'
    attachment.filename = file_path.split('/')[-1]
    attachment.disposition = 'attachment'
    attachment.content_id = 'QR Code'
    mail.add_attachment(attachment)

    sg = SendGrid::API.new(api_key: ENV['SENDGRID_API_KEY'])
    response = sg.client.mail._('send').post(request_body: mail.to_json)
    response
  end

  def self.redis_connection
    @@redis ||= Redis.new(url: ENV['REDIS_URL']) 
  end

  def self.redis_store(phone, data)
    puts "Storing data for #{phone} ... OK"
    data = data.to_json if data.is_a?(Hash)
    redis_connection.set(phone, data)
    redis_load(phone)
  end

  def self.redis_load(phone)
    print "Loading data for #{phone} ... "
    data = redis_connection.get(phone)
    
    if data
      print "OK\n"
      JSON.parse(data, symbolize_names: true) rescue nil
    else
      print "Fail (maybe key not existed)\n"
    end
  end
end
