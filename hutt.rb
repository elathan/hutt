#! /usr/bin/env ruby
# A simple script for fetching Hacker News and store them in Unix mailbox file.
# You can read the news later using mutt (or other e-mail client).
#
# The API for fetching the news is taken from: http://hndroidapi.appspot.com
#
# The code is free. 
#
# --elathan (elias.athanasopoulos@gmail.com)
# 23 February 2013.

require 'uri'
require 'net/http'

require 'rubygems'
require 'json'
require 'pp'


module HN
    HOME_PAGE ="http://hndroidapi.appspot.com/news/format/json/page/"
    COMMENT_PAGE ="http://hndroidapi.appspot.com/nestedcomments/format/json/id/"

    def HN.fetch_home_page()
        Net::HTTP.get_response(URI.parse(HOME_PAGE).host, URI.parse(HOME_PAGE).path)
    end

    def HN.fetch_comments(id)
        Net::HTTP.get_response(URI.parse(COMMENT_PAGE+id).host, URI.parse(COMMENT_PAGE+id).path)
    end

    def HN.decorate(comment)
        comment.gsub!("__BR__", "\n")
        comment.gsub!("&amp;#62;", ">")
        comment.gsub!("&amp;#60;", "<")
        comment
    end

end

class HNStory
    attr_reader :story_id, :title

    def initialize(story, reply = nil)
        @title = story["title"]
        @user = story["user"] || story["username"]
        @story_id = story["item_id"]
        @reply_id = story["id"]
        @story_id = @reply_id if !@story_id
        @url = story["url"]
        @reply = reply 
        @comment = story["comment"]
        @comments_count = story["comments"]
        @children = story["children"]

        @comments = []
        if @children
            @children.each do |child|
                @comments << HNStory.new(child, @reply_id)
            end
        end
    end

    def to_s
        t = Time.now()
        story_date = t.strftime("%a %b %d %H:%M:%S %Y") 
        mailbody  = "From MAILER_DAEMON #{story_date}\n"
        mailbody += "Message-ID: <#{@story_id}>\n"
        mailbody += "In-Reply-To: <#{@reply}>\n" if @reply
        mailbody += "References: <#{@reply}>\n" if @reply
        mailbody += "From: #{@user}\n"
        mailbody += "To: hn@hn.org\n"
        if @title
            mailbody += "Subject: #{@title} (#{@comments_count})\n\n"
        else
            mailbody += "Subject: #{@comment[0..40]}...\n\n"
        end
        mailbody += "#{@url}\n.\n\n" if @url
        mailbody += "#{HN.decorate(@comment)}\n\n" if @comment
        mailbody += @comments.join("\n")
        
        mailbody
    end
end

r = HN.fetch_home_page() 

json_root = JSON.parse(r.body)

hnews = []
json_root.each do |items,stories|
    stories.each do |story|
        hnews << HNStory.new(story) if story['title'] != "NextId"
    end
end

hcomments = []
hnews.each do |article|
    if article.story_id
        r = HN.fetch_comments(article.story_id)
        json_root = JSON.parse(r.body, :max_nesting => 100)
        json_root.each do |items,stories|
            stories.each do |story|
                hcomments << HNStory.new(story, article.story_id) if story['title'] != "NextId"
            end
        end
    end
end


mbox = File.open("mbox", "w")
mbox.truncate(0)
mbox.puts(hnews)
mbox.puts(hcomments)
mbox.close()

system("mutt -f ./mbox")
