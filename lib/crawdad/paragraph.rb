# encoding: utf-8
# Crawdad: Knuth-Plass linebreaking in Ruby.
#
# Copyright February 2010, Brad Ediger. All Rights Reserved.
#
# This is free software. Please see the LICENSE and COPYING files for details.

module Crawdad

  class Paragraph

    include Tokens
    
    def initialize(stream, options={})
      @stream = stream
      @width = options[:width]
      @flagged_penalty = options[:flagged_penalty] || 3000
      @fitness_penalty = options[:fitness_penalty] || 100
    end

    # Width of the paragraph of text. 
    #
    attr_accessor :width

    # Returns an array of optimally sized lines. Each line in the array consists
    # of two elements [tokens, breakpoint]. +tokens+ is an array of tokens taken
    # sequentially from the input stream. +breakpoint+ is a Crawdad::Breakpoint
    # object representing data about the line (primarily the adjustment ratio).
    #
    def lines(threshold=5)
      ls = []
      breakpoints = optimum_breakpoints(threshold)

      # When we break on penalties, we want them to show up at the *end* of the
      # line so that we can put hyphens there if needed. So adjust the
      # breakpoint positions to make that the case.
      breakpoints.each do |b|
        b.position += 1 if token_type(@stream[b.position]) == :penalty
      end

      breakpoints.each_cons(2) do |a, b|
        last = (b == breakpoints[-1]) ? b.position : b.position - 1
        ls << [@stream[a.position..last], b]
      end
      ls
    end

    def optimum_breakpoints(threshold=5)
      active_nodes = [Breakpoint.starting_node]
      each_legal_breakpoint do |item, bi|
        # "Main Loop" (Digital Typography p. 118)

        if active_nodes.empty?
          raise "No feasible solution. Try relaxing threshold."
        end

        ai = 0

        while active_nodes[ai]
          # For each fitness class, keep track of the nodes with the fewest
          # demerits so far.
          best = [nil] * 4

          while a = active_nodes[ai]
            j = a.line + 1 # current line
            r = adjustment_ratio(a, bi)

            if r < -1 || (token_type(item) == :penalty && 
                          penalty_penalty(item) == -Infinity && 
                          a.position < @stream.length - 1)
              active_nodes.delete_at(ai)
            else
              ai += 1
            end

            if r >= -1 && r <= threshold
              d = calculate_demerits(r, item, a) + a.total_demerits
              c = self.class.fitness_class(r)

              # Penalize consecutive lines more than one fitness class away from
              # each other.
              if (c - a.fitness_class).abs > 1
                d += @fitness_penalty
              end

              # Update high scores if this is a new best.
              if best[c].nil? || d < best[c][:demerits]
                best[c] = {:node => a, :demerits => d, :ratio => r}
              end
            end

            # Add nodes to the active list before moving to the next line.
            if (next_node = active_nodes[ai]) && next_node.line >= j
              break
            end
          end

          # If we found any best nodes, add them to the active list.
          if ai && ai < active_nodes.length - 1
            active_nodes[ai, 0] = new_active_nodes(best, bi)
          else
            active_nodes.concat new_active_nodes(best, bi)
          end
        end

      end

      # At this point, everything in active_nodes should point to the final
      # element of our stream (the forced break). Now we pick the one with the
      # fewest total demerits.
      
      node = active_nodes.sort_by { |n| n.total_demerits }.first

      nodes = []
      begin
        nodes.unshift(node)
      end while node = node.previous

      nodes
    end

    # For each item before which we could break, yields two values:
    #
    # +item+::
    #   The item we can break before (glue or penalty).
    # +i+::
    #   The index of +item+ in the stream.
    #
    # Updates the @total_width, @total_stretch, and @total_shrink variables as
    # it moves over the stream, to allow quick calculation of the
    # width/stretch/shrink from the last breakpoint node.
    #
    # Legal breakpoints are either:
    # 
    # * glue immediately following a box, or
    # * a penalty less than positive infinity.
    #
    def each_legal_breakpoint
      @total_width   = 0
      @total_stretch = 0
      @total_shrink  = 0

      @stream.each_with_index do |item, i|
        case token_type(item)
        when :box
          @total_width += token_width(item)
        when :glue
          # We can break here if we immediately follow a box.
          yield(item, i) if token_type(@stream[i-1]) == :box
          @total_width   += token_width(item)
          @total_stretch += glue_stretch(item)
          @total_shrink  += glue_shrink(item)
        when :penalty
          # We can break here unless inhibited by an infinite penalty.
          yield(item, i) unless penalty_penalty(item) == Infinity
        else
          raise ArgumentError, "Unknown item: #{item.inspect}"
        end
      end
    end

    # Calculates the adjustment ratio r by which a line from a to b would have
    # to be adjusted to fit in the given length. r==0 means the natural widths
    # are perfect. r==-1 means all of the shrinkability has been used; r==1
    # means all of the stretchability has been used.
    #
    # Arguments:
    # +node_a+:: 
    #   Breakpoint node of our starting point (on the active list).
    # +b+::
    #   Index (into +stream+) of the breakpoint under consideration.
    #
    def adjustment_ratio(node_a, b)
      item_b = @stream[b]
      # Find the width from a to b.
      w = @total_width - node_a.total_width
      # Add penalty width (hyphen) if we are breaking at a penalty
      w += token_width(item_b) if token_type(item_b) == :penalty
      target_width = @width

      case
      when w < target_width
        stretch = @total_stretch - node_a.total_stretch
        (stretch > 0) ? (target_width - w) / stretch.to_f : Infinity
      when w > target_width
        shrink = @total_shrink - node_a.total_shrink
        (shrink > 0) ? (target_width - w) / shrink.to_f : Infinity
      else 0
      end
    end

    protected

    # Returns the demerits assessed to a break before +new_item+ with adjustment
    # ratio +r+, given the provided active breakpoint.
    #
    def calculate_demerits(r, new_item, active_breakpoint)
      d = case
          when token_type(new_item) == :penalty && 
               penalty_penalty(new_item) >= 0
            (1 + 100*(r.abs ** 3) + penalty_penalty(new_item)) ** 2
          when token_type(new_item) == :penalty && 
               penalty_penalty(new_item) != -Infinity
            ((1 + 100*(r.abs ** 3)) ** 2) - (penalty_penalty(new_item) ** 2)
          else
            (1 + 100*(r.abs ** 3)) ** 2
          end

      old_item = @stream[active_breakpoint.position]
      if token_type(old_item) == :penalty && penalty_flagged?(old_item) && 
         token_type(new_item) == :penalty && penalty_flagged?(new_item)
        d += @flagged_penalty
      end

      d
    end

    # Returns a fitness class number (0=tight, 1=normal, 2=loose, 3=very loose),
    # given the adjustment ratio +r+.
    #
    def self.fitness_class(r)
      case
      when r < -0.5 then 0
      when r <  0.5 then 1
      when r <  1   then 2
      else               3
      end
    end

    # Returns new active nodes for breaks from all "best" breakpoints +best+
    # (lowest demerits within each fitness class) to +b+ (index of the current
    # item in the stream). 
    #
    # The +gamma+ value is used in an optional dominance test; candidate breaks
    # must do better than the optimum fitness class by +gamma+ demerits to be
    # considered.
    #
    # TODO: find optimal value for gamma
    #
    # This is the middle algorithm ("Insert new active nodes for breaks from Ac
    # to b") on p. 119 of Digital Typography.
    #
    def new_active_nodes(best, b, gamma=Infinity)
      lowest_demerits = best.compact.map { |n| n[:demerits] }.min
      new_width, new_stretch, new_shrink = calculate_widths(b)

      new_nodes = []

      # If we found any best nodes, add them to the active list.
      best.each_with_index do |n, fitness_class|
        next if n.nil?
        node, demerits, ratio = n[:node], n[:demerits], n[:ratio]
        next if demerits == Infinity || demerits > lowest_demerits + gamma 

        new_nodes << Breakpoint.new(b, node.line + 1, fitness_class, new_width,
                                    new_stretch, new_shrink, demerits, ratio, 
                                    node)
      end

      new_nodes
    end

    # Compute (\sum w)_{after(b)}, et al. -- total width, stretch, shrink from
    # the active breakpoint to the next box or forced break.
    #
    # Last algorithm on p. 119 of Digital Typography.
    #
    def calculate_widths(b)
      total_width, total_stretch, total_shrink = 
        @total_width, @total_stretch, @total_shrink
      
      @stream[b..-1].each_with_index do |item, i|
        case token_type(item)
        when :box
          break
        when :glue
          total_width   += token_width(item)
          total_stretch += glue_stretch(item)
          total_shrink  += glue_shrink(item)
        when :penalty
          break if penalty_penalty(item) == -Infinity && i > 0
        else
          raise ArgumentError, "Unknown item: #{item.inspect}"
        end
      end

      [total_width, total_stretch, total_shrink]
    end


  end

end
