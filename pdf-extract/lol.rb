# MIT License; please build a better version of this into readwise.
require 'pdf-reader-turtletext'
require 'json'
require 'base64'

class AnnotationRipper
  class Document
    attr_reader :objects

    def initialize(fname)
      @pdf = PDF::Reader.new(fname)
      @tt = PDF::Reader::Turtletext.new(fname)
      @objects = @pdf.objects.reduce({}){|acc,(k,v)|acc[k.id]=v;acc}
    end

    def title
      @pdf.info[:Title]
    end

    def author
      @pdf.info[:Author]
    end

    def annotations
      pages.flat_map(&:annotations)
    end

    def pages
      catalog = objects.values.detect do |data|
        data.is_a?(Hash) && data[:Type] == :Catalog
      end

      pages_obj = objects[catalog[:Pages].id]
      pages_from(pages_obj)
    end

    def text_in_rectangle(page, x, y, z, w)
      textangle = @tt.bounding_box do
        page(page)
        right_of(x)
        above(y)
        left_of(z)
        below(w)
      end
      textangle.text.join.strip
    end

    private

    def pages_from(obj)
      case obj.fetch(:Type)
      when :Pages
        pages = []
        obj.fetch(:Kids, []).each do |kid_ref|
          kid = objects[kid_ref.id]
          pages.concat(pages_from(kid))
          pages.each.with_index { |p, i| p.page_num = i + 1 }
        end
        pages
      when :Page
        [Page.new(self, obj)]
      else
        raise "unexpected Kid type #{obj[:Type]}"
      end
    end
  end

  class Page
    attr_accessor :page_num
    def initialize(document, obj)
      @document = document
      @obj = obj
    end

    def annotations
      return [] unless @obj[:Annots]

      annots = @document.objects[@obj[:Annots].id]
      ret = []
      annots.each do |ref|
        annot = @document.objects[ref.id]
        if annot[:Subtype] == :Highlight
          x, y, z, w = @document.objects[annot[:Rect].id]

          text = @document.text_in_rectangle(@page_num, x, y, z, w)

          ret << Annotation.new(@document.author, @document.title, text)
        end
      end
      ret
    end
  end

  class Annotation
    attr_reader :author, :title, :text

    def initialize(author, title, text)
      @author = author
      @title = title
      @text = text
    end

    def to_json(*)
      {
        author: @author,
        title: @title,
        highlight: @text,
      }.to_json
    end
  end
end

PDFS_PATH = File.expand_path('~/Library/Mobile Documents/com~apple~CloudDocs/Highlighted PDFs')
annots = Dir.glob(PDFS_PATH + '/*.pdf').flat_map do |pdf|
  AnnotationRipper::Document.new(pdf).annotations
end
puts annots.to_json
