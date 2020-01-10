#require 'cupsffi'
require 'active_support'
require 'active_support/core_ext/object/blank'
require "json"
require "rest-firebase"
require_relative "stream_module"
require "fileutils"

class Print

	include StreamModule

	LOCAL_PDF_FILES_DIRECTORY = "pdfs"
	FAILED_PRINTER_STATUSES = [:stopped, :canceled, :aborted,:held]
	FILE_DELETE_HOURS = 6*3600

	attr_accessor :printers
	attr_accessor :printer

	def initialize(args={})
		#self.printers = CupsPrinter.get_all_printer_names
		#self.printer = CupsPrinter.new(self.printers.first)
		raise "Please provide a firebase private key hash " if args[:private_key_hash].nil?
		raise "Please provide an organization id " if args[:organization_id].nil?
		self.private_key_hash = args[:private_key_hash]
	    self.event_source = "organizations/" + args[:organization_id] + "/print_notification"
	    self.on_message_handler_function = "on_print_notification"
	    setup_connection
	end	

	def print_file(file_path)
		job = printer.print_file(file_path)
		!FAILED_PRINTER_STATUSES.include? job.status.to_s.to_sym
	end

	def delete_old_files
		time_now = Time.now
		files_sorted_by_time = Dir['./#{LOCAL_PDF_FILES_DIRECTORY}/*'].select{ |f| (time_now.to_i - (File.mtime(f)).to_i) >  FILE_DELETE_HOURS}
		files_sorted_by_time.each do |f|
			File.delete(f) if File.exist?(f)
		end
	end

	def on_print_notification(data)
		delete_old_files
		unless data.blank?
			data = data["data"].blank? ? data : data["data"]
			data.keys.each do |fn_hash|
				file_url = data[fn_hash]["pdf_url"]
				if file_path = download_file(file_url)
					unless print_file(file_path).blank?
						clear_remote_file(fn_hash)
					end
				end
			end
		end

	end

	def clear_remote_file(hashkey)
		self.connection.delete(self.event_source + "/#{hashkey}")
	end	

	def download_file(url)
		tempfile = Down.download(url)
		filename = tempfile.original_filename
		path = "./" + LOCAL_PDF_FILES_DIRECTORY + filename
		FileUtils.mv(tempfile.path,path)
		path
	end

end

private_key_hash = JSON.parse(IO.read("/home/bhargav/Github/local/config/firebase_credentials.json"))

pr = Print.new({
	:private_key_hash => private_key_hash,
	:organization_id => "Pathofast"
})

pr.watch