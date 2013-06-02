CREATE OR REPLACE PROCEDURE MGCCOP.P_PARSE_COURSE(cin IN OUT mgccop.course_t, json_in VARCHAR2) AS
  LANGUAGE JAVA
  NAME 'CourseParser.parseJson(CourseParser[], java.lang.String)';
  
CREATE OR REPLACE PROCEDURE MGCCOP.P_PARSE_LOAD(lin IN OUT mgccop.load_t, json_in VARCHAR2) AS
  LANGUAGE JAVA
  NAME 'LoadParser.parseJson(LoadParser[], java.lang.String)';
/