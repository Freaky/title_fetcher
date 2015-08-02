#!/usr/bin/env ruby

require 'net/http'
require 'set'

require 'charlock_holmes'
require 'oga'

class ElementGrabber
	attr_reader :read_limit

	class ElementExtractor
		def initialize(element, &callback)
			@element = element
			@callback = callback
			@in_element = false
			@content = []
		end

		def on_element(namespace, name, attrs = {})
			if name == @element
				@in_element = true
			end
		end

		def after_element(namespace, name)
			if @in_element and name == @element
				@callback.call(@content.join)
			end
		end

		def on_text(text)
			if @in_element
				@content << text
			end
		end
	end

	def initialize(tag, read_limit: 32 ** 2 - 1)
		@tag = tag
		@read_limit = Integer(read_limit)
		@encoding_detector = CharlockHolmes::EncodingDetector.new
	end

	def from_uri(uri, redirected_from = Set.new)
		request = Net::HTTP::Get.new uri
		request['Accept'] = 'text/html'

		content = nil

		Net::HTTP.start(uri.host, uri.port) do |http|
			http.request(request) do |response|
				p response
				if response.is_a? Net::HTTPRedirection
					target = response['Location'] or return nil
					if redirected_from.size > 4 or redirected_from.include?(response['Location'])
						return nil # too many redirections or redirect loop
					end
					redirected_from << target
					return from_uri(URI.parse(target), redirected_from)
				end
				break if response.content_type !~ %r{\A(?:text/|application/(?:xml|xhtml))}

				content = nil
				extractor = ElementExtractor.new(@tag) do |text|
					content = text
					throw :done
				end

				reader = Enumerator.new do |parser|
					so_far = 0
					detected_encoding = nil
					encoding_converter = nil
					response.read_body do |chunk|
						unless detected_encoding
							detected_encoding = @encoding_detector.detect(chunk)
						end
						encoded_chunk = CharlockHolmes::Converter.convert(chunk, detected_encoding[:encoding], 'UTF-8')
						parser << encoded_chunk
						so_far += chunk.size

						if so_far > read_limit
							throw :done
						end
					end
				end

				catch(:done) do
					Oga.sax_parse_html(extractor, reader)
				end

				return content
			end
		end
	rescue => e
		#warn("Exception processing #{uri}: #{e.class}, #{e.message}, #{e.backtrace.join("\n")}")
		return content
	end
end

if $0 == __FILE__
	grabber = ElementGrabber.new('title')
	ARGV.each do |url|
		uri = URI.parse(url)
		p grabber.from_uri(uri)
	end
end
