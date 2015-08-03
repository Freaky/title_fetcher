
require 'element_grabber'

class TitleFetcher
	attr_reader :target, :max

	def initialize(target: 80, max: 120)
		@fetcher = ElementGrabber.new('title')
		@target  = Integer(target)
		@max     = Integer(max)
	end

	def fetch(url)
		title = @fetcher.from_url(url) or return nil

		sanitize_and_shorten(title)
	end

	def sanitize_and_shorten(text)
		text = text.gsub(/\n|\t|\s{2,}/, ' ').gsub(/[[:cntrl:]]/, '').strip

		return text if text.size < max

		front = []
		back  = []
		len   = 0

		chunks = text.split(/\b/)
		chunks.map! do |chunk|
			if chunk.size > 20
				chunk.scan(/.{10}/)
			else
				chunk
			end
		end.flatten!

		while len < target and chunks.any?
			3.times do
				front << c = chunks.shift
				len += c.size
			end

			back.unshift c = chunks.pop
			len += c.size
		end

		[front.join, back.join].join(" \u2026 ")[0..max]
	end
end
