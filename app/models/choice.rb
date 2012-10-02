class Choice < ActiveRecord::Base
  acts_as_versioned
  
  belongs_to :question
  belongs_to :creator, :class_name => "Visitor", :foreign_key => "creator_id"
  
  validates_presence_of :creator, :on => :create, :message => "can't be blank"
  validates_presence_of :question, :on => :create, :message => "can't be blank"
  validates_presence_of :data
  #validates_length_of :item, :maximum => 140
  
  has_many :votes
  has_many :losing_votes, :class_name => "Vote", :foreign_key => "loser_choice_id"
  has_many :flags
  has_many :prompts_on_the_left, :class_name => "Prompt", :foreign_key => "left_choice_id"
  has_many :prompts_on_the_right, :class_name => "Prompt", :foreign_key => "right_choice_id"


  has_many :appearances_on_the_left, :through => :prompts_on_the_left, :source => :appearances
  has_many :appearances_on_the_right, :through => :prompts_on_the_right, :source => :appearances
  has_many :skips_on_the_left, :through => :prompts_on_the_left, :source => :skips
  has_many :skips_on_the_right, :through => :prompts_on_the_right, :source => :skips
  named_scope :active, :conditions => { :active => true }
  named_scope :inactive, :conditions => { :active => false}
  named_scope :not_created_by, lambda { |creator_id|
    { :conditions => ["creator_id <> ?", creator_id] }
  }
 
  before_save :cant_change_question_if_it_has_been_voted
  after_save :update_questions_counter
  after_save :update_prompt_queue
  after_save :fixed_counter_cache

  attr_protected :prompts_count, :wins, :losses, :score, :prompts_on_the_right_count, :prompts_on_the_left_count
  attr_accessor :part_of_batch_create

  def cant_change_question_if_it_has_been_voted
    if self.question_id_changed? && self.has_votes?
      self.question_id = self.question_id_was
    end
  end

  def update_questions_counter
    unless part_of_batch_create
      self.question.update_attribute(:inactive_choices_count, self.question.choices.inactive.length)
    end
  end 

  def fixed_counter_cache
    if self.question_id_changed?
      Question.update_counters(self.question_id_was, :choices_count => -1) if self.question_id_was
      Question.update_counters(self.question_id, :choices_count => 1) if self.question_id
    end
  end

  # if changing a choice to active, we want to regenerate prompts
  def update_prompt_queue
    unless part_of_batch_create
      if self.changed.include?('active') && self.active?
        self.question.mark_prompt_queue_for_refill
        if self.question.choices.size - self.question.inactive_choices_count > 1 && self.question.uses_catchup?
          self.question.delay.add_prompt_to_queue
        end
      end
    end
  end
  
  def before_create
    unless self.score
      self.score = 50.0
    end
    unless self.active?
     #puts "this choice was not specifically set to active, so we are now asking if we should auto-activate"
      self.active = question.should_autoactivate_ideas? ? true : false
      #puts "should question autoactivate? #{question.should_autoactivate_ideas?}"
      #puts "will this choice be active? #{self.active}"
    end
    return true #so active record will save
  end
  
  def has_votes?
    !(wins.zero? && losses.zero?)
  end

  def compute_score
    (wins.to_f+1)/(wins+1+losses+1) * 100
  end
  
  def compute_score!
    self.score = compute_score
    save!
  end

  def user_created
    self.creator_id != self.question.creator_id
  end

  def compute_bt_score(btprobs = nil)
      if btprobs.nil?
	      btprobs = self.question.bradley_terry_probs
      end

      p_i = btprobs[self.id]

      total = 0
      btprobs.each do |id, p_j|
	      if id == self.id
		      next
	      end

	      total += (p_i / (p_i + p_j))
      end

      total / (btprobs.size-1)

  end

  def activate!
    (self.active = true)
    self.save!
  end
  
  def deactivate!
    (self.active = false)
    self.save!
  end
  
  protected

  
  def generate_prompts
    #once a choice is added, we need to generate the new prompts (possible combinations of choices)
    #do this in a new process (via delayed jobs)? Maybe just for uploaded ideas
    previous_choices = (self.question.choices - [self])
    return if previous_choices.empty?
    inserts = []

    timestring = Time.now.to_s(:db) #isn't rails awesome?

    #add prompts with this choice on the left
    previous_choices.each do |r|
	inserts.push("(NULL, #{self.question_id}, NULL, #{self.id}, '#{timestring}', '#{timestring}', NULL, 0, #{r.id}, NULL, NULL)")
    end
    #add prompts with this choice on the right 
    previous_choices.each do |l|
	inserts.push("(NULL, #{self.question_id}, NULL, #{l.id}, '#{timestring}', '#{timestring}', NULL, 0, #{self.id}, NULL, NULL)")
    end
    sql = "INSERT INTO `prompts` (`algorithm_id`, `question_id`, `voter_id`, `left_choice_id`, `created_at`, `updated_at`, `tracking`, `votes_count`, `right_choice_id`, `active`, `randomkey`) VALUES #{inserts.join(', ')}"

    Question.update_counters(self.question_id, :prompts_count => 2*previous_choices.size)


    ActiveRecord::Base.connection.execute(sql)

#VALUES (NULL, 108, NULL, 1892, '2010-03-16 11:12:37', '2010-03-16 11:12:37', NULL, 0, 1893, NULL, NULL)
#    INSERT INTO `prompts` (`algorithm_id`, `question_id`, `voter_id`, `left_choice_id`, `created_at`, `updated_at`, `tracking`, `votes_count`, `right_choice_id`, `active`, `randomkey`) VALUES(NULL, 108, NULL, 1892, '2010-03-16 11:12:37', '2010-03-16 11:12:37', NULL, 0, 1893, NULL, NULL)
    #previous_choices.each { |c|
    #  question.prompts.create!(:left_choice => c, :right_choice => self)
    #  question.prompts.create!(:left_choice => self, :right_choice => c)
    #}
  end
end
