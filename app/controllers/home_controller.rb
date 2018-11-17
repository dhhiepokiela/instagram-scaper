

class HomeController < ApplicationController
  include SendGrid

  def index
    load 'instagram'
    @search_form = params[:search].presence || {}
    @results = []
    if @search_form.present?
      @phones = @search_form[:phones].to_s.split(',').reject(&:blank?)
      if @phones.any?
        @phones.each do |phone|
          phone = phone.strip
          @results << Instagram.get_images(phone)
          @results.compact!
        end
      end
    end
  end

  # http://0.0.0.0:3000/01285286828/phone-finder.json
  def phone_finder
    if params[:id]
      render json: Instagram.get_images(params[:id])
    end
  end

  def debug_mode
    # current_session = Instagram.current_session
    # search_field = current_session.find_element(css: '[data-translate-placeholder="STR_INPUT_PHONE_NUMBER"]')
    # search_field.send_key('0933191170')
    # current_session.find_element(css: '[data-translate-inner="STR_FIND_FRIEND"]').click  rescue nil
    # binding.pry
  end
end
