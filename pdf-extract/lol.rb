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

    def text_in_rectangle(page, quadpoints)
      texts = []
      quadpoints.each_slice(8) do |ulx, uly, urx, ury, llx, lly, lrx, lry|
        textangle = @tt.bounding_box do
          page(page)
          right_of(llx)
          above(lly)
          left_of(urx)
          below(ury)
          inclusive(true)
        end
        puts textangle.text.inspect
        puts
        texts.concat(textangle.text)
      end
      texts.join.strip
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
          quadpoints = @document.objects[annot[:QuadPoints].id]

          text = @document.text_in_rectangle(@page_num, quadpoints)

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

glob = '/Users/burke/Library/Mobile Documents/com~apple~CloudDocs/Highlighted PDFs/*.pdf'
annots = Dir.glob(glob).flat_map do |pdf|
  AnnotationRipper::Document.new(pdf).annotations
end
puts annots.to_json
