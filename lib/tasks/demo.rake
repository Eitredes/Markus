namespace :markus do
  desc "Trying to set up demo"
  task(:reset_demo => :environment) do
  
    puts "Destroying old Assignments"
    Assignment.destroy_all
  
    puts "Converting 'a' to 'instructor'"
    i = Admin.find_by_user_name('a')
    i.user_name = "instructor"
    i.first_name = "Jim"
    i.last_name = "Clarke"
    i.save
    
    puts "Renaming 'c5hanson' to 'student'"
    
    s = Student.find_by_user_name('c5hanson')
    s.user_name = 'student'
    s.save

    puts "Generating Assignment A1 and A2..."
    a1 = Assignment.new
    rule = NoLateSubmissionRule.new
    a1.name = "A1"
    a1.description = "Conditionals and Loops"
    a1.message = "Learn to use conditional statements, and loops."
    a1.due_date = Time.now
    a1.group_min = 1
    a1.group_max = 1
    a1.student_form_groups = false
    a1.group_name_autogenerated = true
    a1.group_name_displayed = false
    a1.repository_folder = "A1"
    a1.submission_rule = rule
    a1.save

    a2 = Assignment.new
    rule = NoLateSubmissionRule.new
    a2.name = "A2"
    a2.description = "Cats and Dogs!"
    a2.message = "Basic exercise in Object Oriented Programming.  Implement Animal, Cat, and Dog, as described in class."
    a2.due_date = 1.month.from_now
    a2.group_min = 2
    a2.group_max = 3
    a2.student_form_groups = true
    a2.group_name_autogenerated = true
    a2.group_name_displayed = false
    a2.repository_folder = "A2"
    a2.submission_rule = rule
    a2.save
    
    puts "Creating the Rubric for A1..."
    rubric_criteria = [{:rubric_criterion_name => "Uses Conditionals", :weight => 1}, {:rubric_criterion_name => "Code Clarity", :weight => 2}, {:rubric_criterion_name => "Code Is Documented", :weight => 3}, {:rubric_criterion_name => "Uses For Loop", :weight => 1}]
    default_levels = {:level_0_name => "Quite Poor", :level_0_description => "This criterion was not satisifed whatsoever", :level_1_name => "Satisfactory", :level_1_description => "This criterion was satisfied", :level_2_name => "Good", :level_2_description => "This criterion was satisfied well", :level_3_name => "Great", :level_3_description => "This criterion was satisfied really well!", :level_4_name => "Excellent", :level_4_description => "This criterion was satisfied excellently"}
    rubric_criteria.each do |rubric_criteria|
      rc = RubricCriterion.new
      rc.update_attributes(rubric_criteria)
      rc.update_attributes(default_levels)
      rc.assignment = a1
      rc.save
    end
    
    puts "Create Groupings on A1 and A2 for c5hanson, c5glazun, c5anthei, c5berkel, c5bloche"
    students = ['student', 'c5glazun', 'c5anthei', 'c5berkel', 'c5bloche']
    students.each do |student_name|
      student = Student.find_by_user_name(student_name)
      begin
        student.create_group_for_working_alone_student(a1.id)
        grouping = student.accepted_grouping_for(a1.id)
        grouping.create_grouping_repository_folder
      rescue Exception => e
        puts "Caught exception on #{student_name}"
      end
    end

    puts "Insert a file into student's repository for A1"    
    c5hanson = Student.find_by_user_name('student')

    grouping = c5hanson.accepted_grouping_for(a1.id)
    a1_repo = grouping.group.repo
    txn = a1_repo.get_transaction('student')
    file_data = %|class A1 {
  // This method should sum only positive values
  public static void main(String args[]) {
    // First, I create an array
    double[] ar = {-1.2, 0.5, -0.15, 55.2, -5.2, 8.5, -9.12}
    int sum = 0;
    for (double num : ar) {
      if (num > 0) {
        sum += num
      }
    }
    System.out.println("The sum of the positive values is: " + sum);
  }
}|
    txn.add('A1/A1.java', file_data, 'text/java')
    a1_repo.commit(txn)
    sleep 1
    a1.due_date = Time.now
    a1.save
    
    # Create (empty) Submissions and results for all students besides c5hanson
    students = ['c5glazun', 'c5anthei', 'c5berkel', 'c5bloche']
    students.each do |student_name|
      student = Student.find_by_user_name(student_name)
      grouping = student.accepted_grouping_for(a1.id)
      submission = Submission.create_by_timestamp(grouping, Time.now)
      submission.result.marking_state = Result::MARKING_STATES[:complete]
      submission.result.save
    end

    
  end
end
