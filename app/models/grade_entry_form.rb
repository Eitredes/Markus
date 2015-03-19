require 'encoding'

# GradeEntryForm can represent a test, lab, exam, etc.
# A grade entry form has many columns which represent the questions and their total
# marks (i.e. GradeEntryItems) and many rows which represent students and their
# marks on each question (i.e. GradeEntryStudents).
class GradeEntryForm < ActiveRecord::Base
  has_many                  :grade_entry_items,
                            dependent: :destroy,
                            order: :position

  has_many                  :grade_entry_students,
                            dependent: :destroy

  has_many                  :grades, through: :grade_entry_items

  # Call custom validator in order to validate the date attribute
  # date: true maps to DateValidator (custom_name: true maps to CustomNameValidator)
  # Look in lib/validators/* for more info
  validates                 :date, date: true

  validates_presence_of     :short_identifier
  validates_uniqueness_of   :short_identifier, case_sensitive: true

  accepts_nested_attributes_for :grade_entry_items, allow_destroy: true

  BLANK_MARK = ''

  # The total number of marks for this grade entry form
  def out_of_total
    total = 0
    grade_entry_items.each do |grade_entry_item|
      unless grade_entry_item.bonus
        total += grade_entry_item.out_of
      end
    end
    total
  end

  # Determine the total mark for a particular student, as a percentage
  def calculate_total_percent(grade_entry_student)
    unless grade_entry_student.nil?
      total = grade_entry_student.total_grade
    end

    percent = BLANK_MARK
    out_of = self.out_of_total

    # Check for NA mark or division by 0
    unless total.nil? || out_of == 0
      percent = (total / out_of) * 100
    end
    percent
  end

  # Determine the average of all of the students' marks that have been
  # released so far (return a percentage).
  def calculate_released_average
    total_marks  = 0
    num_released = 0

    grade_entry_students = self.grade_entry_students
                               .where(released_to_student: true)
    grade_entry_students.each do |grade_entry_student|
      total_mark = grade_entry_student.total_grade

      unless total_mark.nil?
        total_marks += total_mark
        num_released += 1
      end
    end

    # Watch out for division by 0
    return 0 if num_released.zero?
    ((total_marks / num_released) / out_of_total) * 100
  end

  # Given two last names, construct an alphabetical category for pagination.
  # eg. If the input is "Albert" and "Auric", return "Al" and "Au".
  def construct_alpha_category(last_name1, last_name2, alpha_categories, i)
    sameSoFar = true
    index = 0
    length_of_shorter_name = [last_name1.length, last_name2.length].min

    # Attempt to find the first character that differs
    while sameSoFar && (index < length_of_shorter_name)
      char1 = last_name1[index].chr
      char2 = last_name2[index].chr

      sameSoFar = (char1 == char2)
      index += 1
    end

    # Form the category name
    if sameSoFar and (index < last_name1.length)
      # There is at least one character remaining in the first name
      alpha_categories[i] << last_name1[0,index+1]
      alpha_categories[i+1] << last_name2[0, index]
    elsif sameSoFar and (index < last_name2.length)
      # There is at least one character remaining in the second name
      alpha_categories[i] << last_name1[0,index]
      alpha_categories[i+1] << last_name2[0, index+1]
    else
      alpha_categories[i] << last_name1[0, index]
      alpha_categories[i+1] << last_name2[0, index]
    end

    alpha_categories
  end

  # An algorithm for determining the category names for alphabetical pagination
  def alpha_paginate(all_grade_entry_students, per_page, total_pages,
                      selected_column)
    alpha_categories = Array.new(2 * total_pages){[]}
    alpha_pagination = []

    # Is total_pages == 0 a necessary check when you can check if there are no students? Clean this up?
    if (total_pages == 0) || (all_grade_entry_students == [])
      return alpha_pagination
    end

    i = 0
    (1..(total_pages - 1)).each do |page|
      grade_entry_students1 = all_grade_entry_students.paginate(per_page: per_page, page: page)
      grade_entry_students2 = all_grade_entry_students.paginate(per_page: per_page, page: page+1)

      # To figure out the category names, we need to keep track of the first and last students
      # on a particular page and the first student on the next page. For example, if these
      # names are "Alwyn, Anderson, and Antheil", the category for this page would be:
      # "Al-And".
      # Enhanced feature: Allow category names by Last Name, First Name,
      # and User Name According to the currently selected column in the
      # spreadsheet. Default is Last Name
      first_student = grade_entry_students1.first.last_name
      last_student = grade_entry_students1.last.last_name
      next_student = grade_entry_students2.first.last_name
      if selected_column == 'first_name'
        first_student = grade_entry_students1.first.first_name
        last_student = grade_entry_students1.last.first_name
        next_student = grade_entry_students2.first.first_name
      elsif selected_column == 'user_name'
        first_student = grade_entry_students1.first.user_name
        last_student = grade_entry_students1.last.user_name
        next_student = grade_entry_students2.first.user_name
      end

      # Update the possible categories
      alpha_categories = self.construct_alpha_category(first_student, last_student,
                                                       alpha_categories, i)
      alpha_categories = self.construct_alpha_category(last_student, next_student,
                                                       alpha_categories, i+1)

      i += 2
    end

    # Handle the last page
    page = total_pages
    grade_entry_students = all_grade_entry_students.paginate(per_page: per_page, page: page)
    # Default is Last Name
    first_student = grade_entry_students.first.last_name
    last_student = grade_entry_students.last.last_name
    if selected_column == 'first_name'
      first_student = grade_entry_students.first.first_name
      last_student = grade_entry_students.last.first_name
    elsif selected_column == 'user_name'
      first_student = grade_entry_students.first.user_name
      last_student = grade_entry_students.last.user_name
    end

    alpha_categories = construct_alpha_category(first_student,
                                                last_student,
                                                alpha_categories,
                                                i)

    # We can now form the category names
    j=0
    (1..total_pages).each do
      alpha_pagination << (alpha_categories[j].max + '-' + alpha_categories[j+1].max)
      j += 2
    end

    return alpha_pagination
  end

  # Get a CSV report of the grades for this grade entry form
  def get_csv_grades_report
    students = Student.all(conditions: {hidden: false}, order: 'user_name')
    CSV.generate do |csv|

      # The first row in the CSV file will contain the question names
      final_result = []
      final_result.push('')
      grade_entry_items.each do |grade_entry_item|
        final_result.push(grade_entry_item.name)
      end
      csv << final_result

      # The second row in the CSV file will contain the question totals
      final_result = []
      final_result.push('')
      grade_entry_items.each do |grade_entry_item|
        final_result.push(grade_entry_item.out_of)
      end
      csv << final_result

      # The rest of the rows in the CSV file will contain the students' grades
      students.each do |student|
        final_result = []
        final_result.push(student.user_name)
        grade_entry_student = self.grade_entry_students
                                  .where(user_id: student.id)
                                  .first

        # Check whether or not we have grades recorded for this student
        if grade_entry_student.nil?
          self.grade_entry_items.each do |grade_entry_item|
            # Blank marks for each question
            final_result.push(BLANK_MARK)
          end
          # Blank total percent
          final_result.push(BLANK_MARK)
        else
          self.grade_entry_items.each do |grade_entry_item|
            grade = grade_entry_student
                      .grades
                      .where(grade_entry_item_id: grade_entry_item.id)
                      .first
            if grade.nil?
              final_result.push(BLANK_MARK)
            else
              final_result.push(grade.grade || BLANK_MARK)
            end
          end
          total_percent = self.calculate_total_percent(grade_entry_student)
          final_result.push(total_percent)
        end
        csv << final_result
      end
    end
  end

  # Parse a grade entry form CSV file.
  # grades_file is the CSV file to be parsed
  # grade_entry_form is the grade entry form that is being updated
  # invalid_lines will store all problematic lines from the CSV file
  def self.parse_csv(grades_file, grade_entry_form, invalid_lines, encoding)
    num_updates = 0
    num_lines_read = 0
    names = []
    totals = []
    grades_file = StringIO.new(grades_file.read.utf8_encode(encoding))

    # Parse the question names
    CSV.parse(grades_file.readline) do |row|
      unless CSV.generate_line(row).strip.empty?
        names = row
        num_lines_read += 1
      end
    end

    # Parse the question totals
    CSV.parse(grades_file.readline) do |row|
      unless CSV.generate_line(row).strip.empty?
        totals = row
        num_lines_read += 1
      end
    end

    # Create/update the grade entry items
    begin
      GradeEntryItem.create_or_update_from_csv_rows(names, totals, grade_entry_form)
      num_updates += 1
    rescue RuntimeError => e
      invalid_lines << names.join(',')
      error = e.message.is_a?(String) ? e.message : ''
      invalid_lines << totals.join(',') + ': ' + error unless invalid_lines.nil?
    end

    # Parse the grades
    CSV.parse(grades_file.read) do |row|
      next if CSV.generate_line(row).strip.empty?
      begin
        if num_lines_read > 1
          GradeEntryStudent.create_or_update_from_csv_row(row,
                                                          grade_entry_form,
                                                          grade_entry_form.grade_entry_items,
                                                          names)
          num_updates += 1
        end
        num_lines_read += 1
      rescue RuntimeError => e
        error = e.message.is_a?(String) ? e.message : ''
        invalid_lines << row.join(',') + ': ' + error unless invalid_lines.nil?
      end
    end
    return num_updates
  end

end
