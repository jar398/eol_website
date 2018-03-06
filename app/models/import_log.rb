class ImportLog < ActiveRecord::Base
  belongs_to :resource
  has_many :import_events, inverse_of: :import_log

  scope :successful, -> { where("completed_at IS NOT NULL") }

  def log(body, options = nil)
    options ||= {}
    cat = options[:cat] || :starts
    chop_into_text_chunks(body).each do |chunk|
      import_events << ImportEvent.create(import_log: self, cat: cat, body: chunk)
    end
  end

  def chop_into_text_chunks(str)
    chunks = []
    while str.size > 65_500
      chunks << str[0..65_500]
      str = str[65_500..-1]
    end
    chunks << str
    chunks
  end

  def complete
    update_attribute(:completed_at, Time.now)
    update_attribute(:status, "completed")
    resource.touch # Ensure that we see the resource as having changed
    log('Complete', cat: :ends)
  end

  def fail(e)
    e.backtrace.reverse.each_with_index do |trace, i|
      last if trace =~ /\/bundler/
      last if i > 9 # Too much info, man!
      if i > 2
        # TODO: Add other filters here...
        next unless trace =~ /eol_website/
      end
      trace.gsub!(/^.*\/gems\//, 'gem:') # Remove ruby version stuff...
      trace.gsub!(/^.*\/ruby\//, 'ruby:') # Remove ruby version stuff...
      trace.gsub!(/^.*\/eol_website\//, './') # Remove website path..
      log(trace, cat: :errors)
    end
    log(e.message.gsub(/#<(\w+):0x[0-9a-f]+>/, '\\1'), cat: :errors) # I don't need the memory information for models
    update_attribute(:failed_at, Time.now)
    update_attribute(:status, e.message[0..250])
  end
end