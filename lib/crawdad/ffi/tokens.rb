require 'ffi'

module Crawdad
  module Tokens
    extend FFI::Library

    Type = enum(:box, :glue, :penalty)
    
    def token_type(token)
      token[:type]
    end

    class Box < FFI::Struct
      layout :type,    Type,
             :width,   :float,
             :content, :string

      def inspect
        "(box %.2f %s)" % [self[:width], self[:content].inspect]
      end
    end

    def box(width, content)
      Box.new(Crawdad::Paragraph::C.make_box(width, content))
    end

    def box_content(b)
      b[:content]
    end

    class Glue < FFI::Struct
      layout :type,    Type,
             :width,   :float,
             :stretch, :float,
             :shrink,  :float

      def inspect
        "(glue %.2f %.2f %.2f)" % [self[:width], self[:stretch], self[:shrink]]
      end
    end

    def glue(width, stretch, shrink)
      Glue.new(Crawdad::Paragraph::C.make_glue(width, stretch, shrink))
    end

    def glue_stretch(glue)
      glue[:stretch]
    end

    def glue_shrink(glue)
      glue[:shrink]
    end

    class Penalty < FFI::Struct
      layout :type,    Type,
             :width,   :float,
             :penalty, :float,
             :flagged, :int

      def inspect
        "(penalty %.2f %.2f#{" F" if self[:flagged] == 1})" %
          [self[:penalty], self[:width]]
      end
    end
    
    def penalty(penalty, width=0.0, flagged=false)
      Penalty.new(Crawdad::Paragraph::C.make_penalty(width, penalty, flagged))
    end

    def penalty_penalty(p)
      p[:penalty]
    end

    # TODO: this might return true/false. problem?
    def penalty_flagged?(p)
      p[:flagged] != 0
    end

    def token_width(token)
      token[:width]
    end

  end
end
