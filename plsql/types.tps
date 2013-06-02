CREATE OR REPLACE TYPE MGCCOP.COURSE_T AS OBJECT (
   account_id VARCHAR2(10),
   course_code VARCHAR2(50),
    default_view VARCHAR2(50),
    id VARCHAR2(50),
    name VARCHAR2(50),
    start_at VARCHAR2(50),
    end_at VARCHAR2(50),
    public_syllabus VARCHAR2(50),
    hide_final_grades VARCHAR2(50),
    sis_course_id VARCHAR2(50),
   workflow_state VARCHAR2(50),
   ics VARCHAR2(200),
    CONSTRUCTOR FUNCTION COURSE_T
    RETURN SELF AS RESULT
);

CREATE OR REPLACE TYPE BODY MGCCOP.COURSE_T IS
 CONSTRUCTOR FUNCTION COURSE_T
   RETURN SELF AS RESULT
 IS
 BEGIN
   RETURN;
 END;
END;

CREATE OR REPLACE TYPE MGCCOP.loadwarn_t AS TABLE OF VARCHAR2(500);

CREATE OR REPLACE TYPE MGCCOP.loadwarno_t AS TABLE OF mgccop.loadwarn_t;

CREATE OR REPLACE TYPE MGCCOP.LOAD_T AS OBJECT (
   created_at VARCHAR2(50),
   ended_at VARCHAR2(50),
   updated_at VARCHAR2(50),
   progress VARCHAR2(3),
   id NUMBER,
   import_type VARCHAR2(50),
   supplied_batches mgccop.loadwarn_t,
   warnings  MGCCOP.LOADWARNO_T,
   c_accounts VARCHAR2(10),
   c_terms VARCHAR2(10),
   c_abstract_courses VARCHAR2(10),
   c_courses VARCHAR2(10),
   c_sections VARCHAR2(10),
   c_xlists VARCHAR2(10),
   c_users VARCHAR2(10),
   c_enrollments VARCHAR2(10),
   c_groups VARCHAR2(10),
   c_group_memberships VARCHAR2(10),
   c_grade_publishing_results VARCHAR2(10),
   CONSTRUCTOR FUNCTION LOAD_T
    RETURN SELF AS RESULT
);

CREATE OR REPLACE TYPE BODY MGCCOP.LOAD_T IS
 CONSTRUCTOR FUNCTION LOAD_T
   RETURN SELF AS RESULT
 IS
 BEGIN
   RETURN;
 END;
END;
/