require 'open3'
require 'json'
require 'net/http'
require 'digest/sha1'

rwsessionid, _, t = Open3.capture3(
  'security',
  'find-generic-password',
  '-w', # print only the password
  '-l', 'readwise-rwsessionid' 
)
abort 'missing rwsessionid' unless t.success?


def highlights_from_api(rwsessionid)
  cookie = "rwsessionid=#{rwsessionid.chomp}"
  Net::HTTP.start('readwise.io', 443, use_ssl: true) do |http|
    resp = http.get('/munger', { 'Cookie' => cookie })
    abort 'GET failed' unless resp.code.to_i == 200
    return JSON.parse(resp.body)
  end
end

data = highlights_from_api(rwsessionid)

def format_highlight(highlight:, note:, author:, source:, medium:)
  digest = Digest::SHA1.hexdigest([highlight,author,source,medium].join("\1"))
  [digest, highlight, source, author].join("\t") + "\n"
end

def to_tsv(data)
  out = ""
  data.fetch('data').map do |book|
    highlights = book.delete('highlights')
    highlights.each do |highlight|
      out << format_highlight(
        highlight: highlight['highlight'],
        note:      highlight['note'],
        author:    book['author'],
        source:    book['source'],
        medium:    book['medium'],
      )
    end
  end
  out
end

puts to_tsv(data)
