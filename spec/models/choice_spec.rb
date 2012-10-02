require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Choice do
  
  it {should belong_to :question}
  it {should belong_to :creator}
  it {should have_many :flags}
  it {should have_many :votes}
  it {should have_many :prompts_on_the_left}
  it {should have_many :prompts_on_the_right}
  it {should validate_presence_of :question}
  it {should validate_presence_of :creator}
  it {should validate_presence_of :data}
  
  before(:each) do
    @aoi_clone = Factory.create(:email_confirmed_user)
    @visitor= Factory.create(:visitor, :site => @aoi_clone)
    @question = Factory.create(:aoi_question, :name => "Which do you like better?",
				:site => @aoi_clone, 
				:creator => @visitor)
    
    @valid_attributes = {
      :creator => @visitor,
      :question_id => @question.id,
      :data => 'hi there'
    }

    @unreasonable_value = 9999
    @protected_attributes = {}
    [ :prompts_count,
      :wins,
      :losses,
      :score,
      :prompts_on_the_right_count,
      :prompts_on_the_left_count
    ].each{|key| @protected_attributes[key] = @unreasonable_value}

  end

  it "should create a new instance given valid attributes" do
    Choice.create!(@valid_attributes)
  end

  it "should not manually set protected attributes when created" do
    choice1 = Choice.create!(@valid_attributes.merge(@protected_attributes))
    @protected_attributes.each_key do |key|
      choice1[key].should_not == @unreasonable_value
    end
  end

  it "should not allow mass assignment of protected attributes" do
    choice1 = Choice.create!(@valid_attributes)
    choice1.update_attributes(@protected_attributes)
    @protected_attributes.each_key do |key|
      choice1[key].should_not == @unreasonable_value
    end
  end

  it "should deactivate a choice" do
    choice1 = Choice.create!(@valid_attributes.merge(:data => '1234'))
    choice1.deactivate!
    choice1.should_not be_active
  end

  it "should update a question's counter cache on creation" do
	  # not an allour ideas question
	  question = Factory.create(:question, :site => @aoi_clone, :creator => @visitor)
	  question.choices_count.should == 0
	  question.choices.size.should == 0
          Choice.create!(@valid_attributes.merge(:question_id => question.id))
	  question.reload
	  question.choices_count.should == 1
	  question.choices.size.should == 1
  end

  it "should update a question's counter cache on update" do
	  # not an allour ideas question
	  question = Factory.create(:question, :site => @aoi_clone, :creator => @visitor)
	  question.choices_count.should == 0
	  question.choices.size.should == 0
    c = Choice.create!(@valid_attributes.merge(:question_id => question.id))
    c.update_attributes!(:question_id => question.id)
	  question.reload
	  question.choices_count.should == 1
	  question.choices.size.should == 1
  end

  it "should be able to change category" do
    choice = Choice.create!(@valid_attributes)
    new_question = Factory.create(:question)
    choice.update_attributes!(:question_id => new_question.id)
    choice.reload.question_id.should == new_question.id
  end

  it "shouldn't be able to change category if it already have votes" do
    choice = Choice.create!(@valid_attributes)
    choice.stub!(:has_votes?).and_return(true)
    new_question = Factory.create(:question)
    choice.update_attributes!(:question_id => new_question.id)
    choice.reload.question_id.should == @question.id
  end

  it "should update a question's counter cache on activation" do
	  prev_inactive = @question.inactive_choices_count
          choice1 = Choice.create!(@valid_attributes.merge(:data => '1234'))
	  choice1.deactivate!
	  @question.reload
	  @question.inactive_choices_count.should == prev_inactive + 1
	  choice1.activate!
	  @question.reload
	  @question.inactive_choices_count.should == prev_inactive
	  choice1.should be_active
  end

  it "should create a delayed job on activation" do
    choice1 = Choice.create!(@valid_attributes.merge(:data => '1234'))
    proc { choice1.activate! }.should change(Delayed::Job, :count).by(1)
  end

  it "should update a question's counter cache on deactivation" do 
	  prev_inactive = @question.inactive_choices_count
          choice1 = Choice.create!(@valid_attributes.merge(:data => '1234'))
	  choice1.deactivate!
	  @question.reload
	  @question.inactive_choices_count.should == prev_inactive + 1
  end
  it "should have a default score of 50" do 
          choice1 = Choice.create!(@valid_attributes)
	  choice1.score.should == 50 
  end
  it "correctly compute a score based on wins and losses" do 
          choice1 = Choice.create!(@valid_attributes)
	  choice1.wins = 30
	  choice1.losses = 70
	  choice1.compute_score.should be_close(30,1)
  end
  it "compute score and save" do 
          choice1 = Choice.create!(@valid_attributes)
	  choice1.score.should == 50
	  choice1.wins = 30
	  choice1.losses = 70
	  choice1.compute_score!
	  choice1.score.should be_close(30, 1)
  end

  it "determines whether a choice is admin created" do
	  admin_choice = @question.choices.first
	  admin_choice.user_created.should be_false
  end
  it "determines whether a choice is user created" do
  	  new_visitor = Factory.create(:visitor, :site => @aoi_clone)
	  user_choice = Factory.create(:choice, :question => @question, :creator => new_visitor)
	  user_choice.user_created.should be_true
  end

  describe "voting updates things" do
    before do
      @prompt = @question.choose_prompt
      @winning_choice = @prompt.left_choice
      @losing_choice = @prompt.right_choice
      vote = Vote.create!(:choice_id => @winning_choice.id,
                          :loser_choice_id => @losing_choice.id,
                          :question_id => @question.id,
                          :voter_id => @visitor.id,
                          :prompt_id => @prompt.id )
     end
   
     it "should update score on a win" do
	  @winning_choice.reload
          @winning_choice.score.should be_close(67, 1)
     end
     it "should update score on a loss" do
	  @losing_choice.reload
          @losing_choice.score.should be_close(33,1)
     end
     it "should update win count on a win" do
	  @winning_choice.reload
          @winning_choice.wins.should == 1
          @winning_choice.losses.should == 0
     end
     it "should update loss count on a loss" do
	  @losing_choice.reload
          @losing_choice.wins.should == 0
          @losing_choice.losses.should == 1
     end
     it "should have votes, if it either lost or won" do
       @winning_choice.reload.has_votes?.should be_true
       @losing_choice.reload.has_votes?.should be_true
     end
     it "shouldn't have votes if it never won or lost" do
       choice = Factory.build(:choice)
       choice.wins.should == 0
       choice.losses.should == 0
       choice.has_votes?.should be_false
     end
  end
end
