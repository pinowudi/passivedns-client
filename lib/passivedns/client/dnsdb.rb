# DESCRIPTION: this is a module for pdns.rb, primarily used by pdnstool.rb, to query the Farsight Security passive DNS database
# details on the API are at https://api.dnsdb.info/
# to request an API key, please email dnsdb-api at farsightsecurity dot com.
require 'net/http'
require 'net/https'

module PassiveDNS
	class DNSDB
		attr_accessor :debug
		@@base="https://api.dnsdb.info/lookup"
		
		def initialize(config="#{ENV['HOME']}/.dnsdb-query.conf")
			@debug = false
			if File.exist?(config)
				@key = File.open(config).readline.chomp
				if @key =~ /^[0-9a-f]{64}$/
					# pass
				elsif @key =~ /^APIKEY=\"([0-9a-f]{64})\"/
					@key = $1
				else
					raise "Format of configuration file (default: #{ENV['HOME']}/.dnsdb-query.conf) is:\nAPIKEY=\"<key>\"\nE.g.,\nAPIKEY=\"d41d8cd98f00b204e9800998ecf8427ed41d8cd98f00b204e9800998ecf8427e\"\n"
				end
			else
				raise "Configuration file for DNSDB is required for intialization\nFormat of configuration file (default: #{ENV['HOME']}/.dnsdb-query.conf) is:\nAPIKEY=\"<key>\"\nE.g.,\nAPIKEY=\"d41d8cd98f00b204e9800998ecf8427ed41d8cd98f00b204e9800998ecf8427e\"\n"
			end
		end

		def parse_json(page,response_time)
			res = []
			raise "Error: unable to parse request" if page =~ /Error: unable to parse request/
			# need to remove the json_class tag or the parser will crap itself trying to find a class to align it to
			rows = page.split(/\n/)
			rows.each do |row|
				record = JSON.parse(row)
				record['rdata'] = [record['rdata']] if record['rdata'].class == String
				record['rdata'].each do |rdata|
					if record['time_first']
						res << PDNSResult.new('DNSDB',response_time,record['rrname'],rdata,record['rrtype'],0,Time.at(record['time_first'].to_i).utc.strftime("%Y-%m-%dT%H:%M:%SZ"),Time.at(record['time_last'].to_i).utc.strftime("%Y-%m-%dT%H:%M:%SZ"),record['count'])
					else
						res << PDNSResult.new('DNSDB',response_time,record['rrname'],rdata,record['rrtype'])
					end
				end
			end
			res
		rescue Exception => e
			$stderr.puts "DNSDB Exception: #{e}"
			$stderr.puts page
			raise e
		end

		def lookup(label, limit=nil)
			$stderr.puts "DEBUG: DNSDB.lookup(#{label})" if @debug
			Timeout::timeout(240) {
				url = nil
				if label =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(\/\d{1,2})?$/
					label = label.gsub(/\//,',')
					url = "#{@@base}/rdata/ip/#{label}"
				else
					url = "#{@@base}/rrset/name/#{label}"
				end
				url = URI.parse url
				http = Net::HTTP.new(url.host, url.port)
				http.use_ssl = (url.scheme == 'https')
				http.verify_mode = OpenSSL::SSL::VERIFY_NONE
				http.verify_depth = 5
        path = url.path
        if limit
          path << "?limit=#{limit}"
        end
				request = Net::HTTP::Get.new(path)
				request.add_field("User-Agent", "Ruby/#{RUBY_VERSION} passivedns-client rubygem v#{PassiveDNS::Client::VERSION}")
				request.add_field("X-API-Key", @key)
				request.add_field("Accept", "application/json")
				t1 = Time.now
				response = http.request(request)
				t2 = Time.now
				$stderr.puts response.body if @debug
				parse_json(response.body,t2-t1)
			}
		rescue Timeout::Error => e
			$stderr.puts "DNSDB lookup timed out: #{label}"
		end
	end
end