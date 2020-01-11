require 'cupsffi'
require 'active_support'
require 'active_support/core_ext/object/blank'
require "json"
require "rest-firebase"
require_relative "stream_module"
require "fileutils"
require "net/http"
require 'resolv-replace'
require 'base64'
require 'jwt'
require 'down'

RestFirebase.class_eval do 
	
	attr_accessor :private_key_hash

	def query
    	{:access_token => auth}
  	end

  	def get_jwt
		puts Base64.encode64(JSON.generate(self.private_key_hash))
		# Get your service account's email address and private key from the JSON key file
		$service_account_email = self.private_key_hash["client_email"]
		$private_key = OpenSSL::PKey::RSA.new self.private_key_hash["private_key"]
		  now_seconds = Time.now.to_i
		  payload = {:iss => $service_account_email,
		             :sub => $service_account_email,
		             :aud => self.private_key_hash["token_uri"],
		             :iat => now_seconds,
		             :exp => now_seconds + 1, # Maximum expiration time is one hour
		             :scope => 'https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/firebase.database'

		         }
		  JWT.encode payload, $private_key, "RS256"
		
	end

	def generate_access_token
	  uri = URI.parse(self.private_key_hash["token_uri"])
	  https = Net::HTTP.new(uri.host, uri.port)
	  https.use_ssl = true
	  req = Net::HTTP::Post.new(uri.path)
	  req['Cache-Control'] = "no-store"
	  req.set_form_data({
	    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
	    assertion: get_jwt
	  })

	  resp = JSON.parse(https.request(req).body)
	  resp["access_token"]
	end

	def generate_auth opts={}
		generate_access_token
	end
 
end


class Print

	include StreamModule

	LOCAL_PDF_FILES_DIRECTORY = "pdfs"
	FAILED_PRINTER_STATUSES = [:stopped, :canceled, :aborted,:held]
	FILE_DELETE_HOURS = 6*3600

	attr_accessor :printers
	attr_accessor :printer
	attr_accessor :job
	attr_accessor :printing_on

	def initialize(args={})
		self.printers = CupsPrinter.get_all_printer_names
		self.printer = CupsPrinter.new(self.printers.first)
		self.printing_on = args[:printing_on] || false
		raise "Please provide a firebase private key hash " if args[:private_key_hash].nil?
		raise "Please provide an organization id " if args[:organization_id].nil?
		self.private_key_hash = args[:private_key_hash]
	    self.event_source = "organizations/" + args[:organization_id] + "/print_notification"
	    puts "event source is: #{self.event_source}"
	    self.on_message_handler_function = "on_print_notification"
	    setup_connection
	end	

	def print_file(file_path)
		if self.job.blank?
			puts "no current job so proceeding to queue"
		else
			puts "current job status: #{self.job.status}"
			return if self.job.status != :completed
		end
		self.job = self.printer.print_file(file_path)
		puts "job status : #{self.job.status}"
		!FAILED_PRINTER_STATUSES.include? self.job.status.to_s.to_sym
	end

=begin
	def delete_old_files
		time_now = Time.now
		files_sorted_by_time = Dir['./#{LOCAL_PDF_FILES_DIRECTORY}/*'].select{ |f| (time_now.to_i - (File.mtime(f)).to_i) >  FILE_DELETE_HOURS}
		files_sorted_by_time.each do |f|
			File.delete(f) if File.exist?(f)
		end
	end
=end

	def on_print_notification(data)
		puts "incoming data:#{data}"
		unless data.blank?
			path_key = nil
			unless data["path"] == "/"
				path_key = data["path"].gsub(/\//,'')
			end
			puts "path key becomes: #{path_key}"
			data = data["data"]

			unless data.blank?
				if data.is_a? Hash
					puts "data is:#{data}"
					if data["pdf_url"]
						file_url = data["pdf_url"]
						process_url(file_url,path_key)
					else
						data.keys.each do |fn_hash|
							file_url = data[fn_hash]["pdf_url"]
							process_url(file_url,fn_hash)
						end
					end

				end
			end
		end
	end

	def clear_remote_file(hashkey)
		puts "result of clearing remote file"
		puts self.connection.delete(self.event_source + "/#{hashkey}")
	end	

	def process_url(file_url,fn_hash)
		if file_url =~ /^http/
		    # Correct URL
			if tempfile = download_file(file_url)
				puts "file download success"
				unless self.printing_on.blank?
					unless print_file(tempfile.path).blank?
						clear_remote_file(fn_hash)
					else
						puts "printing deferred as previous job is incomplete"
					end
				else
					puts "PRINTING IS OFF, so not printing."
					clear_remote_file(fn_hash)
				end
			end
		else
			puts "url is not valid, will be cleared from remote.: #{file_url}"
			#clear_remote_file(fn_hash)
		end
	end

	def download_file(url)
		tempfile = Down.download(url)
	end

end


private_key_hash = JSON.parse(IO.read(ENV["FIREBASE_PRIVATE_KEY_PATH"]))
puts private_key_hash

pr = Print.new({
	:private_key_hash => private_key_hash,
	:organization_id => "5e196674acbcd63d3d43b238-Pathofast",
	:printing_on => true
})

pr.watch