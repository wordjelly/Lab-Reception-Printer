require 'cupsffi'

class Print

	include StreamModule

	attr_accessor :printers
	attr_accessor :printer

	def initialize(args={})
		self.printers = CupsPrinter.get_all_printer_names
		self.printer = CupsPrinter.new(self.printers.first)
		raise "Please provide a firebase private key hash " if args[:private_key_hash].blank?
		raise "Please provide an organization id " if args[:organization_id].blank?
		self.private_key_hash = args[:private_key_hash]
	    self.event_source = "organizations/" + args[:organization_id]
	    self.on_message_handler_function = "on_print_notification"
	    setup_connection
	end	

	def print_file(file_path)
		job = printer.print_file(file_path)
	end


	def on_print_notification(data)
=begin
		unless data.blank?
			data = data["data"].blank? ? data : data["data"]
			unless data["delete_order"].blank?
				unless data["delete_order"]["order_id"].blank?
					delete_completed_order(data["delete_order"]["order_id"])
				end
			end
			unless data["trigger_lis_poll"].blank?
				unless data["trigger_lis_poll"]["epoch"].blank?
					new_poll_LIS_for_requisition(data["trigger_lis_poll"]["epoch"].to_i)
				end
			end
		else

		end
=end
	end

	## put -> printing_order/base64 {data}
	## f.delete -> that node (once your done)

	def clear_downloaded_file(file_name)
		## from the key hash.
		## and the local storage?
		## we need down also.
	end

	def download_file(url)
				
	end

end

private_key_hash = JSON.parse(IO.read("firebase_credentials.json"))
pr = Print.new({
	:private_key_hash => private_key_hash,
	:organization_id => "Pathofast"
})