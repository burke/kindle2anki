require 'open3'
require 'kindle_highlights'
require 'json'

email = begin
  File.read(File.join(__dir__, ".email")).chomp
rescue Errno::ENOENT
  abort "create a file at kindle2anki/.email containing your email address."
end

pass, stat = Open3.capture2(
  "/usr/bin/security", "find-generic-password", "-a", email, "-w", "-l", "kindle",
)
unless stat.success?
  abort "open Keychain Access.app, press Command-N, and enter 'kindle', then your kindle email and password, then run again."
end
pass.chomp!

class Kindle
  def initialize(user, pass, path = 'data.json')
    @user = user
    @pass = pass
    @path = path
  end

  def update
    html = HTMLEntities.new
    kindle = KindleHighlights::Client.new(email_address: @user, password: @pass) 
    @highlights = []

    kindle.books.each do |book|
      kindle.highlights_for(book.asin).each do |highlight|
        @highlights << {
          asin:     book.asin,
          title:    book.title,
          author:   book.author,
          location: highlight.location,
          text:     highlight.text,
        }
      end
    end
  end

  def save 
    File.open(@path, "w+") do |fp| 
      fp << @highlights.to_json
    end
  end

  def highlights
    @highlights ||= JSON.load(open(@path))
  end
end

kindle = Kindle.new(email, pass)
kindle.update
kindle.save
