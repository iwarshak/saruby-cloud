require 'base64'
require 'openssl'
require 'digest/sha1'
require 'right_aws'
require 'sdb/active_sdb'
RightAws::ActiveSdb.establish_connection

class PicturesController < ApplicationController
  
  def home
    @pictures = Picture.select(:all, :order => "updated_at desc")
  end
  
  def destroy
    @picture = Picture.select params[:id]
    @picture.remove_stored_images
    @picture.delete
    redirect_to :action => "home"
  end
  
  def check_for_updates
    render :update do |page|
      picture = Picture.select(params[:id])
      if picture.done_processing?
        page.replace_html(params[:sane_picture_id], :partial => "picture", :object => picture )
        page << "check_#{params[:sane_picture_id]}=false"
      else
        render :nothing => true
      end
    end
  end
  
  def upload
    policy = {
      "expiration" => (Time.now + 1.hour).gmtime.iso8601, 
      "conditions" => 
        [
          {"bucket" => Picture::UPLOAD_BUCKET}, 
          ["starts-with", "$key", "uploads/"],
          {"acl" => "private"},
          {"success_action_redirect" => REDIRECT_URL},
          ["content-length-range", 0, 10_000_000]
        ]
    }
    @policy_document = Base64.encode64(policy.to_json).gsub("\n","")

    @signature = Base64.encode64(
        OpenSSL::HMAC.digest(
            OpenSSL::Digest::Digest.new('sha1'), 
            ENV["AWS_SECRET_ACCESS_KEY"], @policy_document)
        ).gsub("\n","")
  
  end
  
  def callback
    Picture.create_with_jobs(params[:key])
    flash[:notice] = "File #{params[:key]} was successfully uploaded."
    redirect_to "/"
  end
  
  def purge_db
    Picture.find(:all).each {|c| c.delete }
    respond_to do |format|
      format.html { redirect_to :action => upload }
      format.js do 
        render :update do |page|
          page.replace_html('db-size', "#{Picture.find(:all).size}")
        end
      end
    end
  end
  
  def purge_queue
    sqs = RightAws::SqsGen2.new
    convert_queue = sqs.queue("convert")
    convert_queue.clear
    respond_to do |format|
      format.html { redirect_to :action => upload }
      format.js do 
        render :update do |page|
          page.replace_html('queue-size', "#{convert_queue.size}")
        end
      end
    end
  end
        
end
