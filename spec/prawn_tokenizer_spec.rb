# encoding: utf-8
# Crawdad: Knuth-Plass linebreaking in Ruby.
#
# Copyright February 2010, Brad Ediger. All Rights Reserved.
#
# This is free software. Please see the LICENSE and COPYING files for details.

require File.join(File.expand_path(File.dirname(__FILE__)), "spec_helper")

describe "Prawn tokenizer" do

  before(:each) do
    @pdf = CachedWidthDocument
    @tokenizer = PrawnTokenizer.new(@pdf)
  end

  # These specs are inspired by Digital Typography, pp. 72-73

  # (1)
  it "should prepend an empty box for paragraph indentation" do
    unindented_stream = @tokenizer.paragraph("foo")
    indented_stream   = @tokenizer.paragraph("foo", :indent => 12)

    # Ensure there is an extra box for the indentation.
    indented_stream.grep(Box).length.should == 
      unindented_stream.grep(Box).length + 1

    # Indentation box should be the width requested.
    indented_stream.first.should.be.a.kind_of(Box)
    indented_stream.first.width.should == 12

    # Box content should have one entry for each of the boxes.
    unindented_stream[0].content.should == "foo"
    indented_stream[0].content.should == ""
    indented_stream[1].content.should == "foo"
  end

  # (2)
  it "should create boxes for each word, including punctuation" do
    stream = @tokenizer.paragraph("this is a test.")
    boxes = stream.grep(Box)

    boxes.length.should == 4
    boxes.zip(%w[this is a test.]).each do |box, word|
      box.width.should == @pdf.width_of(word)
    end

    boxes.map { |b| b.content}.should == %w[this is a test.]
  end

  # TODO: insert flagged penalties at hyphenation points
  
  # (3)
  it "should insert glue between words" do
    stream = @tokenizer.paragraph("this is a test.")
    3.times{ stream.pop } # remove finishing elements
    stream.map{ |i| i.class }.should == [Box, Glue, Box, Glue, Box, Glue, Box]

    interword_width = @pdf.width_of(" ")
    stream.grep(Glue).each do |glue|
      glue.width.should == interword_width
    end
  end

  # (4)
  it "should follow explicit hyphens with zero-width flagged penalties" do
    stream = @tokenizer.paragraph("cul-de-sac")
    3.times{ stream.pop } # remove finishing elements
    stream.map{ |i| i.class }.should == [Box, Penalty, Box, Penalty, Box]

    # check boxes
    stream[0].width.should == @pdf.width_of("cul-")
    stream[2].width.should == @pdf.width_of("de-")
    stream[4].width.should == @pdf.width_of("sac")

    stream.grep(Box).map { |b| b.content}.should == %w[cul- de- sac]

    # check penalties
    stream[1].width.should.be.zero
    stream[1].should.be.flagged
    stream[3].width.should.be.zero
    stream[3].should.be.flagged
  end

  # (5)
  it "should finish paragraphs with a disallowed break, finishing glue, and" +
     "forced break" do
    stream = @tokenizer.paragraph("foo bar baz")
    forced_break = stream.pop
    finishing_glue = stream.pop
    disallowed_break = stream.pop
    
    disallowed_break.should.be.a.kind_of(Penalty)
    disallowed_break.penalty.should == Infinity

    finishing_glue.should.be.a.kind_of(Glue)
    finishing_glue.width.should.be.zero
    finishing_glue.stretch.should == Infinity

    forced_break.should.be.a.kind_of(Penalty)
    forced_break.penalty.should == -Infinity
    # check this, because we will break here for sure
    forced_break.width.should.be.zero
  end

  it "should insert extra space after sentence-ending periods" do
    stream = @tokenizer.paragraph("bork bork bork. bork bork bork")
    normal_glue = stream.detect { |t| t.is_a?(Glue) }

    i = stream.find_index { |t| t.is_a?(Box) && t.content == 'bork.' }
    sentence_glue = stream[i+1]

    sentence_glue.should.be.a.kind_of(Glue)
    sentence_glue.width.should.be > normal_glue.width
  end

  describe "with hyphenation" do
    
    it "should insert flagged penalties at each hyphenation point" do
      stream = @tokenizer.paragraph("testing", :hyphenation => true)
      3.times { stream.pop }

      stream.map { |t| t.class }.should == [Box, Penalty, Box]

      stream[0].content.should == "test"
      stream[1].width.should == @pdf.width_of('-')
      stream[1].should.be.flagged
      stream[2].content.should == "ing"
    end

    it "should not affect manually hyphenated words" do
      stream = @tokenizer.paragraph("play-thing", :hyphenation => true)
      3.times { stream.pop }

      stream.map { |t| t.class }.should == [Box, Penalty, Box]
      stream[0].content.should == 'play-'
      stream[1].width.should.be.zero
      stream[1].should.be.flagged
      stream[2].content.should == 'thing'
    end

  end

end
