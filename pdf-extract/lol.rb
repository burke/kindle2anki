require 'pdf-reader-turtletext'

class AnnotationRipper
  class Document # :nodoc:
    attr_reader :objects

    def initialize(fname)
      @pdf = PDF::Reader.new(fname)
      @tt = PDF::Reader::Turtletext.new(fname)
      @objects = @pdf.objects.each_with_object({}) { |(k, v), a| a[k.id] = v }
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
      quadpoints.each_slice(8) do |_ulx, _uly, urx, ury, llx, lly, _lrx, _lry|
        textangle = @tt.bounding_box do
          page(page)
          right_of(llx)
          above(lly)
          left_of(urx)
          below(ury)
          inclusive(true)
        end
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
          pages.concat(pages_from(objects[kid_ref.id]))
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

  class Page # :nodoc:
    attr_accessor :page_num
    def initialize(document, obj)
      @document = document
      @obj = obj
    end

    def annotations
      return [] unless @obj[:Annots]

      @document.objects[@obj[:Annots].id].each_with_object([]) do |ref, acc|
        annot = @document.objects[ref.id]
        next unless annot[:Subtype] == :Highlight

        quadpoints = @document.objects[annot[:QuadPoints].id]
        text = @document.text_in_rectangle(@page_num, quadpoints)
        acc << Annotation.new(@document.author, @document.title, text, annot[:Contents])
      end
    end
  end

  class Annotation # :nodoc:
    attr_reader :author, :title, :text, :note

    def initialize(author, title, text, note)
      @author = author
      @title = title
      @text = text
      @note = note
    end

    def to_json(*)
      {
        highlight: @text,
        note: @note,
        author: @author,
        source: @title,
        medium: 'pdf'
      }.to_json
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require 'json'

  pdfs_path = File.expand_path(
    '~/Library/Mobile Documents/com~apple~CloudDocs/Highlighted PDFs'
  )

  annots = Dir.glob(pdfs_path + '/*.pdf').flat_map do |pdf|
    begin
      AnnotationRipper::Document.new(pdf).annotations
    rescue => e
      # STDERR.puts "Failed to handle document #{pdf}"
      nil
    end
  end.compact

  puts annots.to_json
end
