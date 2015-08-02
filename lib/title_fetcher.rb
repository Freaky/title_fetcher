#!/usr/bin/env ruby

require_relative 'element_grabber'

class TitleFetcher
	attr_reader :target, :max

	def initialize(target: 80, max: 120)
		@fetcher = ElementGrabber.new('title')
	end

	def self.fetch(url)
		title = @fetcher.from_url(url) or return nil

		if title.size > max
		end
	end
end
