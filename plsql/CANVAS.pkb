/* Formatted on 6/1/2013 7:15:54 PM (QP5 v5.163.1008.3004) */
CREATE OR REPLACE PACKAGE BODY MGCCOP.canvas
AS
   wallet_path   CONSTANT VARCHAR2 (100) := '/d07/production/canvas/wallet/';
   wallet_pass   CONSTANT VARCHAR2 (50) := 'espkh232';
   inst_token    CONSTANT VARCHAR2 (100) := '1613~J2F54qJ3tjoFgFmlTM8fF5i1gf1qDJGlelwWPeFVHm0cFx6E7nPLwNArcSV7ij31';

   /* Returns employee address if one exists, otherwise
    * returns the student address */
   FUNCTION f_get_canvas_email (pidm_in IN NUMBER)
      RETURN goremal.goremal_email_address%TYPE
   IS
      CURSOR c_email
      IS
         SELECT 1,
                DECODE (NVL (goremal_preferred_ind, 'N'),  'Y', 1,  'N', 2),
                goremal_activity_date,
                ROWID,
                goremal_email_address EA
           FROM goremal
          WHERE goremal_pidm = pidm_in
                AND (goremal_email_address LIKE '%@mgccc.edu' OR goremal_email_address LIKE '%@mgccc.cc.ms.us')
         UNION
         SELECT 2,
                DECODE (NVL (goremal_preferred_ind, 'N'),  'Y', 1,  'N', 2),
                goremal_activity_date,
                ROWID,
                goremal_email_address EA
           FROM goremal
          WHERE goremal_pidm = pidm_in AND goremal_email_address LIKE '%@bulldogs.mgccc.edu'
         ORDER BY 1,
                  2,
                  3 DESC,
                  4 DESC;

      eaddr   c_email%ROWTYPE;
   BEGIN
      OPEN c_email;
      FETCH c_email INTO eaddr;
      CLOSE c_email;
      RETURN eaddr.EA;
   END;

   /*Returns plaintext self-service pin from pin audit table*/
   FUNCTION f_get_canvas_pwd (pidm_in IN NUMBER)
      RETURN gorpaud.gorpaud_pin%TYPE
   IS
      CURSOR c_pin
      IS
           SELECT gorpaud_pin
             FROM gorpaud
            WHERE gorpaud_pidm = pidm_in AND gorpaud_chg_ind = 'P'
         ORDER BY gorpaud_activity_date DESC;

      pin   gorpaud.gorpaud_pin%TYPE;
   BEGIN
      OPEN c_pin;

      FETCH c_pin INTO pin;

      CLOSE c_pin;

      RETURN pin;
   END;

   /* Returns full JSON status response of a submitted SIS Import */
   FUNCTION f_load_status (load_id IN VARCHAR2)
      RETURN VARCHAR2
   IS
      creq    UTL_HTTP.req;
      cresp   UTL_HTTP.resp;
      url     VARCHAR2 (500);
      buf     VARCHAR2 (32767);
   BEGIN
      UTL_HTTP.set_wallet (PATH => 'file:' || wallet_path, password => wallet_pass);
      
      url := 'https://mgccc.instructure.com/api/v1/accounts/11/sis_imports/' || load_id;
      
      creq := UTL_HTTP.begin_request (url, 'GET', 'HTTP/1.1');
      UTL_HTTP.set_header (creq, 'Authorization', 'Bearer ' || inst_token);
      cresp := UTL_HTTP.get_response (creq);

      BEGIN
         -- utl_http.read_text(cresp, buf,32767);
         UTL_HTTP.read_text (cresp, buf, 4000);
      EXCEPTION
         WHEN OTHERS
         THEN
            NULL;
      END;

      UTL_HTTP.end_response (cresp);
      RETURN buf;
   END f_load_status;

   /* Returns the workflow status of specified course 
     * Possible return values are unavailable (unpublished),
     * available (published), and NULL (invalid course id)*/
   FUNCTION f_course_stat (course_id IN VARCHAR2)
      RETURN VARCHAR2
   IS
      creq     UTL_HTTP.req;
      cresp    UTL_HTTP.resp;
      url      VARCHAR2 (500);
      buf      VARCHAR2 (32767);
      status   VARCHAR (4000);
      course  mgccop.course_t;
   BEGIN
      UTL_HTTP.set_wallet (PATH => 'file:' || wallet_path, password => wallet_pass);
      url := 'https://mgccc.instructure.com/api/v1/courses/sis_course_id:' || course_id;
      creq := UTL_HTTP.begin_request (url, 'GET', 'HTTP/1.1');
      UTL_HTTP.set_header (creq, 'Authorization', 'Bearer ' || inst_token);
      cresp := UTL_HTTP.get_response (creq);

      BEGIN
         -- utl_http.read_text(cresp, buf,32767);
         UTL_HTTP.read_text (cresp, buf, 4000);
      EXCEPTION
         WHEN OTHERS
         THEN
            NULL;
      END;

      UTL_HTTP.end_response (cresp);
      status := REGEXP_REPLACE (buf, '.+"workflow_state":"([[:alpha:]]+)?.*', '\1');
      DBMS_OUTPUT.put_line (status);
      RETURN status;
   END f_course_stat;

   /*Updates status of specified course to "available"
    * aka "publishes" the course */
   PROCEDURE p_offer_course (crsid_in IN VARCHAR2)
   IS
      creq           UTL_HTTP.req;
      cresp          UTL_HTTP.resp;
      put_url        VARCHAR2 (500);
      paramstr       VARCHAR2 (500);
      payload_size   NUMBER;
      buf            VARCHAR2 (32767);
   BEGIN
      UTL_HTTP.set_wallet (PATH => 'file:' || wallet_path, password => wallet_pass);
      paramstr := 'event=offer&course_ids[]=sis_course_id:' || crsid_in;
      payload_size := LENGTHB (paramstr);

      put_url := 'https://mgccc.instructure.com/api/v1/accounts/11/courses';


      creq := UTL_HTTP.begin_request (put_url, 'PUT', 'HTTP/1.1');
      UTL_HTTP.set_header (creq, 'Content-Type', 'application/x-www-form-urlencoded');
      UTL_HTTP.set_header (creq, 'Authorization', 'Bearer ' || inst_token);
      UTL_HTTP.set_header (creq, 'Content-Length', payload_size);

      UTL_HTTP.write_text (creq, paramstr);

      cresp := UTL_HTTP.get_response (creq);
      UTL_HTTP.read_text (cresp, buf);
      DBMS_OUTPUT.put_line (buf);
      UTL_HTTP.end_response (cresp);
      UTL_FILE.fclose_all;
   END p_offer_course;

   /*Checks the status of all courses having a start date
    * within 24 hours on either side of sysdate.
    * If the course is unpublished, publishes*/
   PROCEDURE p_offer_upcoming
   IS
      CURSOR c_sections
      IS
         SELECT section_id
           FROM mgccop.canvas_sections
          WHERE ABS (section_sdate - SYSDATE) < 1;
   BEGIN
      FOR r_section IN c_sections
      LOOP
         IF f_course_stat (r_section.section_id) = 'unpublished'
         THEN
            p_offer_course (r_section.section_id);
            DBMS_OUTPUT.put_line (r_section.section_id || ' should be published now.');
         END IF;
      END LOOP;
   END p_offer_upcoming;

   /*Generates csv containing currently active term records.
    *Inputs are a batch stamp and an output file path
    *Sending all terms in every incremental and batch upload*/
   PROCEDURE p_get_terms (bstamp_in IN VARCHAR2, fpath_in IN VARCHAR2)
   IS
      csv_name   VARCHAR2 (70);
      csv_rpt    UTL_FILE.FILE_TYPE;
      bstamp     VARCHAR2 (12);
      v_row      NUMBER;

      CURSOR c_terms
      IS
         SELECT * FROM mgccop.v_canvas_terms;
   BEGIN
      csv_name := 'terms_' || bstamp_in || '.csv';
      v_row := 0;

      FOR r_term IN c_terms
      LOOP
         v_row := c_terms%ROWCOUNT;

         IF c_terms%ROWCOUNT = 1
         THEN
            csv_rpt := UTL_FILE.FOPEN (fpath_in, csv_name, 'w');
            UTL_FILE.put_line (csv_rpt, 'term_id,name,status,start_date,end_date');
         END IF;

         UTL_FILE.put_line (
            csv_rpt,
               r_term.cterm_code
            || ','
            || r_term.cterm_desc
            || ','
            || 'active'
            || ','
            || TO_CHAR (r_term.cterm_tstart, 'YYYY-MM-DD HH24:MI:SS')
            || '-06:00'
            || ','
            || TO_CHAR (r_term.cterm_tend, 'YYYY-MM-DD HH24:MI:SS')
            || '-06:00');

         IF r_term.cterm_mccbterm IS NOT NULL
         THEN
            UTL_FILE.put_line (
               csv_rpt,
                  r_term.cterm_mccbterm
               || ','
               || r_term.cterm_desc
               || ' (MSVCC),'
               || 'active'
               || ','
               || TO_CHAR (r_term.cterm_ostart, 'YYYY-MM-DD HH24:MI:SS')
               || '-06:00'
               || ','
               || TO_CHAR (r_term.cterm_oend, 'YYYY-MM-DD HH24:MI:SS')
               || '-06:00');
         END IF;
      END LOOP;

      IF v_row > 0
      THEN
         UTL_FILE.fclose (csv_rpt);
      END IF;
   END p_get_terms;

    /*Generates csv containing all uncreated or changed users.
     *This process is only additive.  No deletes are sent.
     *Inputs are a batch stamp and an output file path
     *For use in incremental uploads.*/
   PROCEDURE p_get_users (bstamp_in IN VARCHAR2, fpath_in IN VARCHAR2)
   IS
      csv_name   VARCHAR2 (70);
      csv_rpt    UTL_FILE.FILE_TYPE;
      bstamp     VARCHAR2 (12);
      v_row      NUMBER;

      CURSOR c_users
      IS
         SELECT * FROM mgccop.v_canvas_users;
   BEGIN
      csv_name := 'users_' || bstamp_in || '.csv';
      v_row := 0;

      FOR r_user IN c_users
      LOOP
         v_row := c_users%ROWCOUNT;

         IF c_users%ROWCOUNT = 1
         THEN
            csv_rpt := UTL_FILE.FOPEN (fpath_in, csv_name, 'w');
            UTL_FILE.put_line (csv_rpt, 'user_id,login_id,password,first_name,last_name,email,status');
         END IF;

         --In Banner, but not batched yet
         IF r_user.batch_pidm IS NULL AND r_user.banner_pidm IS NOT NULL
         THEN
            INSERT INTO mgccop.canvas_users
                 VALUES (r_user.banner_pidm,
                         r_user.banner_id,
                         r_user.banner_password,
                         r_user.banner_fname,
                         r_user.banner_lname,
                         r_user.banner_email,
                         'active',
                         bstamp_in,
                         bstamp_in);

            UTL_FILE.put_line (
               csv_rpt,
                  '211.'
               || r_user.banner_id
               || ','
               || r_user.banner_id
               || ',"'
               || r_user.banner_password
               || '","'
               || r_user.banner_fname
               || '","'
               || r_user.banner_lname
               || '","'
               || r_user.banner_email
               || '",'
               || 'active');
         --Any updatable fields changed?
         ELSIF r_user.banner_pidm IS NOT NULL
               AND (   (NVL (r_user.banner_id, 'X') != NVL (r_user.batch_id, 'X'))
                    OR (NVL (r_user.banner_lname, 'X') != NVL (r_user.batch_lname, 'X'))
                    OR (NVL (r_user.banner_fname, 'X') != NVL (r_user.batch_fname, 'X'))
                    OR (NVL (r_user.banner_fname, 'X') != NVL (r_user.batch_fname, 'X'))
                    OR (NVL (r_user.banner_password, 'X') != NVL (r_user.batch_password, 'X'))
                    OR (NVL (r_user.banner_email, 'X') != NVL (r_user.batch_email, 'X')))
         THEN
            UPDATE mgccop.canvas_users
               SET user_id = r_user.banner_id,
                   user_password = r_user.banner_password,
                   user_fname = r_user.banner_fname,
                   user_lname = r_user.banner_lname,
                   user_email = r_user.banner_email,
                   user_last_batch_id = bstamp_in
             WHERE user_pidm = r_user.banner_pidm;

            UTL_FILE.put_line (
               csv_rpt,
                  '211.'
               || r_user.banner_id
               || ','
               || r_user.banner_id
               || ',"'
               || r_user.banner_password
               || '","'
               || r_user.banner_fname
               || '","'
               || r_user.banner_lname
               || '","'
               || r_user.banner_email
               || '",'
               || r_user.batch_status);
         END IF;
      END LOOP;

      COMMIT;

      IF v_row > 0
      THEN
         UTL_FILE.fclose (csv_rpt);
      END IF;
   END p_get_users;

   /*Generates csv containing ALL active users. 
    *For use in full batch upload */
   PROCEDURE p_all_users (bstamp_in IN VARCHAR2, fpath_in IN VARCHAR2)
   IS
      csv_name   VARCHAR2 (70);
      csv_rpt    UTL_FILE.FILE_TYPE;
      bstamp     VARCHAR2 (12);
      v_row      NUMBER;

      CURSOR c_users
      IS
         SELECT *
           FROM mgccop.v_canvas_users
          WHERE banner_pidm IS NOT NULL;
   BEGIN
      csv_name := 'all_users_' || bstamp_in || '.csv';
      v_row := 0;

      FOR r_user IN c_users
      LOOP
         v_row := c_users%ROWCOUNT;

         IF c_users%ROWCOUNT = 1
         THEN
            csv_rpt := UTL_FILE.FOPEN (fpath_in, csv_name, 'w');
            UTL_FILE.put_line (csv_rpt, 'user_id,login_id,password,first_name,last_name,email,status');
         END IF;

         --In Banner, but not batched yet
         IF r_user.batch_pidm IS NULL AND r_user.banner_pidm IS NOT NULL
         THEN
            INSERT INTO mgccop.canvas_users
                 VALUES (r_user.banner_pidm,
                         r_user.banner_id,
                         r_user.banner_password,
                         r_user.banner_fname,
                         r_user.banner_lname,
                         r_user.banner_email,
                         'active',
                         bstamp_in,
                         bstamp_in);

            UTL_FILE.put_line (
               csv_rpt,
                  '211.'
               || r_user.banner_id
               || ','
               || r_user.banner_id
               || ',"'
               || r_user.banner_password
               || '","'
               || r_user.banner_fname
               || '","'
               || r_user.banner_lname
               || '","'
               || r_user.banner_email
               || '",'
               || 'active');
         ELSE
            UPDATE mgccop.canvas_users
               SET user_id = r_user.banner_id,
                   user_password = r_user.banner_password,
                   user_fname = r_user.banner_fname,
                   user_lname = r_user.banner_lname,
                   user_email = r_user.banner_email,
                   user_last_batch_id = bstamp_in
             WHERE user_pidm = r_user.banner_pidm;

            UTL_FILE.put_line (
               csv_rpt,
                  '211.'
               || r_user.banner_id
               || ','
               || r_user.banner_id
               || ',"'
               || r_user.banner_password
               || '","'
               || r_user.banner_fname
               || '","'
               || r_user.banner_lname
               || '","'
               || r_user.banner_email
               || '",'
               || r_user.batch_status);
         END IF;
      END LOOP;

      COMMIT;

      IF v_row > 0
      THEN
         UTL_FILE.fclose (csv_rpt);
      END IF;
   END p_all_users;

   /*Get new or changed subaccounts.
    *For use in incremental uploads */
   PROCEDURE p_get_accounts (bstamp_in IN VARCHAR2, fpath_in IN VARCHAR2)
   IS
      csv_name   VARCHAR2 (70);
      csv_rpt    UTL_FILE.FILE_TYPE;
      bstamp     VARCHAR2 (12);
      v_row      NUMBER;

      CURSOR c_accounts
      IS
         SELECT * FROM mgccop.v_canvas_accounts;
   BEGIN
      csv_name := 'accounts_' || bstamp_in || '.csv';
      v_row := 0;

      FOR r_account IN c_accounts
      LOOP
         v_row := c_accounts%ROWCOUNT;

         IF c_accounts%ROWCOUNT = 1
         THEN
            csv_rpt := UTL_FILE.FOPEN (fpath_in, csv_name, 'w');
            UTL_FILE.put_line (csv_rpt, 'account_id,parent_account_id,name,status');
         END IF;

         IF r_account.batch_status IS NULL AND r_account.banner_status = 'active'
         THEN
            INSERT INTO mgccop.canvas_accounts
                 VALUES (r_account.banner_account_id,
                         r_account.banner_account_name,
                         r_account.banner_status,
                         bstamp_in,
                         bstamp_in,
                         r_account.banner_parent_id);

            UTL_FILE.put_line (
               csv_rpt,
                  r_account.banner_account_id
               || ','
               || r_account.banner_parent_id
               || ',"'
               || r_account.banner_account_name
               || '",'
               || r_account.banner_status);
         ELSIF NVL (r_account.banner_status, 'X') = 'active'
               AND ( (NVL (r_account.banner_account_name, 'X') != NVL (r_account.batch_account_name, 'X'))
                    OR (NVL (r_account.banner_parent_id, 'X') != NVL (r_account.batch_parent_id, 'X')))
         THEN
            UPDATE mgccop.canvas_accounts
               SET account_name = r_account.banner_account_name,
                   account_status = r_account.banner_status,
                   account_last_batch_id = bstamp_in,
                   account_parent_id = r_account.banner_parent_id
             WHERE account_id = r_account.banner_account_id;

            UTL_FILE.put_line (
               csv_rpt,
                  r_account.banner_account_id
               || ','
               || r_account.banner_parent_id
               || ',"'
               || r_account.banner_account_name
               || '",'
               || r_account.banner_status);
         END IF;
      END LOOP;

      COMMIT;

      IF v_row > 0
      THEN
         UTL_FILE.fclose (csv_rpt);
      END IF;
   END p_get_accounts;

   /*Get ALL subaccounts.  For use in a full batch upload*/
   PROCEDURE p_all_accounts (bstamp_in IN VARCHAR2, fpath_in IN VARCHAR2)
   IS
      csv_name   VARCHAR2 (70);
      csv_rpt    UTL_FILE.FILE_TYPE;
      bstamp     VARCHAR2 (12);
      v_row      NUMBER;

      CURSOR c_accounts
      IS
         SELECT *
           FROM mgccop.v_canvas_accounts
          WHERE banner_account_id IS NOT NULL;
   BEGIN
      csv_name := 'all_accounts_' || bstamp_in || '.csv';
      v_row := 0;

      FOR r_account IN c_accounts
      LOOP
         v_row := c_accounts%ROWCOUNT;

         IF c_accounts%ROWCOUNT = 1
         THEN
            csv_rpt := UTL_FILE.FOPEN (fpath_in, csv_name, 'w');
            UTL_FILE.put_line (csv_rpt, 'account_id,parent_account_id,name,status');
         END IF;

         IF r_account.batch_status IS NULL AND r_account.banner_status = 'active'
         THEN
            INSERT INTO mgccop.canvas_accounts
                 VALUES (r_account.banner_account_id,
                         r_account.banner_account_name,
                         r_account.banner_status,
                         bstamp_in,
                         bstamp_in,
                         r_account.banner_parent_id);

            UTL_FILE.put_line (
               csv_rpt,
                  r_account.banner_account_id
               || ','
               || r_account.banner_parent_id
               || ',"'
               || r_account.banner_account_name
               || '",'
               || r_account.banner_status);
         ELSE
            UPDATE mgccop.canvas_accounts
               SET account_name = r_account.banner_account_name,
                   account_status = r_account.banner_status,
                   account_last_batch_id = bstamp_in,
                   account_parent_id = r_account.banner_parent_id
             WHERE account_id = r_account.banner_account_id;

            UTL_FILE.put_line (
               csv_rpt,
                  r_account.banner_account_id
               || ','
               || r_account.banner_parent_id
               || ',"'
               || r_account.banner_account_name
               || '",'
               || r_account.banner_status);
         END IF;
      END LOOP;

      COMMIT;

      IF v_row > 0
      THEN
         UTL_FILE.fclose (csv_rpt);
      END IF;
   END p_all_accounts;

   /*Generate csv for new, deleted, or changed sections AND courses.
     *Sections and courses are created as a single unit.
     *This generates two files for use in incremental uploads*/
   PROCEDURE p_get_sections (bstamp_in IN VARCHAR2, fpath_in IN VARCHAR2)
   IS
      csv_courses_name    VARCHAR2 (70);
      csv_sections_name   VARCHAR2 (70);
      csv_courses_rpt     UTL_FILE.FILE_TYPE;
      csv_sections_rpt    UTL_FILE.FILE_TYPE;
      bstamp              VARCHAR2 (12);
      v_row               NUMBER;

      CURSOR c_sections
      IS
         SELECT * FROM mgccop.v_canvas_sections;
   BEGIN
      csv_courses_name := 'courses_' || bstamp_in || '.csv';
      csv_sections_name := 'sections_' || bstamp_in || '.csv';
      v_row := 0;

      FOR r_section IN c_sections
      LOOP
         v_row := c_sections%ROWCOUNT;

         IF c_sections%ROWCOUNT = 1
         THEN
            csv_courses_rpt := UTL_FILE.FOPEN (fpath_in, csv_courses_name, 'w');
            csv_sections_rpt := UTL_FILE.FOPEN (fpath_in, csv_sections_name, 'w');
            UTL_FILE.put_line (csv_courses_rpt,
                               'course_id,short_name,long_name,account_id,term_id,status,start_date,end_date');
            UTL_FILE.put_line (csv_sections_rpt, 'section_id,course_id,name,status,start_date,end_date');
         END IF;

         IF r_section.batch_status IS NULL AND r_section.banner_status = 'active'
         THEN
            INSERT INTO mgccop.canvas_sections
                 VALUES (r_section.banner_term,
                         r_section.banner_crn,
                         r_section.banner_section_id,
                         r_section.banner_short_name,
                         r_section.banner_long_name,
                         r_section.banner_account_id,
                         r_section.banner_status,
                         r_section.banner_start_date,
                         r_section.banner_end_date,
                         bstamp_in,
                         bstamp_in);

            UTL_FILE.put_line (
               csv_courses_rpt,
                  r_section.banner_section_id
               || ','
               || '"'
               || r_section.banner_short_name
               || '",'
               || '"'
               || r_section.banner_long_name
               || '",'
               || r_section.banner_account_id
               || ','
               || r_section.banner_term
               || ','
               || r_section.banner_status
               || ','
               || TO_CHAR (r_section.banner_start_date, 'YYYY-MM-DD HH24:MI:SS')
               || '-06:00'
               || ','
               || TO_CHAR (r_section.banner_end_date, 'YYYY-MM-DD HH24:MI:SS')
               || '-06:00');

            UTL_FILE.put_line (
               csv_sections_rpt,
                  r_section.banner_section_id
               || ','
               || r_section.banner_section_id
               || ','
               || '"'
               || r_section.banner_long_name
               || '",'
               || r_section.banner_status
               || ','
               || TO_CHAR (r_section.banner_start_date, 'YYYY-MM-DD HH24:MI:SS')
               || '-06:00'
               || ','
               || TO_CHAR (r_section.banner_end_date, 'YYYY-MM-DD HH24:MI:SS')
               || '-06:00');
         ELSIF r_section.batch_status = 'active' AND r_section.banner_status IS NULL
         THEN
            DELETE FROM mgccop.canvas_sections
                  WHERE section_term = r_section.batch_term AND section_crn = r_section.batch_crn;

            UTL_FILE.put_line (
               csv_courses_rpt,
                  r_section.batch_section_id
               || ','
               || '"'
               || r_section.batch_sname
               || '",'
               || '"'
               || r_section.batch_long_name
               || '",'
               || r_section.batch_account_id
               || ','
               || r_section.batch_term
               || ','
               || 'deleted'
               || ','
               || TO_CHAR (r_section.batch_start_date, 'YYYY-MM-DD HH24:MI:SS')
               || '-06:00'
               || ','
               || TO_CHAR (r_section.batch_end_date, 'YYYY-MM-DD HH24:MI:SS')
               || '-06:00');

            UTL_FILE.put_line (
               csv_sections_rpt,
                  r_section.batch_section_id
               || ','
               || r_section.batch_section_id
               || ','
               || '"'
               || r_section.batch_long_name
               || '",'
               || 'deleted'
               || ','
               || TO_CHAR (r_section.batch_start_date, 'YYYY-MM-DD HH24:MI:SS')
               || '-06:00'
               || ','
               || TO_CHAR (r_section.batch_end_date, 'YYYY-MM-DD HH24:MI:SS')
               || '-06:00');
         ELSIF r_section.banner_status IS NOT NULL
               AND (   (NVL (r_section.banner_section_id, 'X') != NVL (r_section.batch_section_id, 'X'))
                    OR (NVL (r_section.banner_short_name, 'X') != NVL (r_section.batch_sname, 'X'))
                    OR (NVL (r_section.banner_long_name, 'X') != NVL (r_section.batch_long_name, 'X'))
                    OR (NVL (r_section.banner_account_id, 'X') != NVL (r_section.batch_account_id, 'X'))
                    OR (NVL (r_section.banner_start_date, '01-JAN-1900') !=
                           NVL (r_section.batch_start_date, '01-JAN-1900'))
                    OR (NVL (r_section.banner_end_date, '01-JAN-1900') != NVL (r_section.batch_end_date, '01-JAN-1900')))
         THEN
            UPDATE mgccop.canvas_sections
               SET section_id = r_section.banner_section_id,
                   section_sname = r_section.banner_short_name,
                   section_lname = r_section.banner_long_name,
                   section_account = r_section.banner_account_id,
                   section_status = r_section.banner_status,
                   section_sdate = r_section.banner_start_date,
                   section_edate = r_section.banner_end_date,
                   section_last_batch_id = bstamp_in
             WHERE section_term = r_section.banner_term AND section_crn = r_section.banner_crn;

            UTL_FILE.put_line (
               csv_courses_rpt,
                  r_section.banner_section_id
               || ','
               || '"'
               || r_section.banner_short_name
               || '",'
               || '"'
               || r_section.banner_long_name
               || '",'
               || r_section.banner_account_id
               || ','
               || r_section.banner_term
               || ','
               || r_section.banner_status
               || ','
               || TO_CHAR (r_section.banner_start_date, 'YYYY-MM-DD HH24:MI:SS')
               || '-06:00'
               || ','
               || TO_CHAR (r_section.banner_end_date, 'YYYY-MM-DD HH24:MI:SS')
               || '-06:00');

            UTL_FILE.put_line (
               csv_sections_rpt,
                  r_section.banner_section_id
               || ','
               || r_section.banner_section_id
               || ','
               || '"'
               || r_section.banner_long_name
               || '",'
               || r_section.banner_status
               || ','
               || TO_CHAR (r_section.banner_start_date, 'YYYY-MM-DD HH24:MI:SS')
               || '-06:00'
               || ','
               || TO_CHAR (r_section.banner_end_date, 'YYYY-MM-DD HH24:MI:SS')
               || '-06:00');
         END IF;
      END LOOP;

      COMMIT;

      IF v_row > 0
      THEN
         UTL_FILE.fclose (csv_courses_rpt);
         UTL_FILE.fclose (csv_sections_rpt);
      END IF;
   END p_get_sections;
   
   /*Generate csv for all sections AND courses for the specified term.
    *Sections and courses are created as a single unit.
    *This generates two files for use in batch uploads
    *Since sections and courses are term-specific
    *batch mode uploads can be done. */
   PROCEDURE p_term_sections (term_in IN VARCHAR2, bstamp_in IN VARCHAR2, fpath_in IN VARCHAR2)
   IS
      csv_courses_name    VARCHAR2 (70);
      csv_sections_name   VARCHAR2 (70);
      csv_courses_rpt     UTL_FILE.FILE_TYPE;
      csv_sections_rpt    UTL_FILE.FILE_TYPE;
      bstamp              VARCHAR2 (12);
      v_row               NUMBER;

      CURSOR c_sections
      IS
         SELECT *
           FROM mgccop.v_canvas_sections
          WHERE banner_term = term_in;
   BEGIN
      csv_courses_name := 'courses_' || bstamp_in || '.csv';
      csv_sections_name := 'sections_' || bstamp_in || '.csv';
      v_row := 0;

      FOR r_section IN c_sections
      LOOP
         v_row := c_sections%ROWCOUNT;

         IF c_sections%ROWCOUNT = 1
         THEN
            csv_courses_rpt := UTL_FILE.FOPEN (fpath_in, csv_courses_name, 'w');
            csv_sections_rpt := UTL_FILE.FOPEN (fpath_in, csv_sections_name, 'w');
            UTL_FILE.put_line (csv_courses_rpt,
                               'course_id,short_name,long_name,account_id,term_id,status,start_date,end_date');
            UTL_FILE.put_line (csv_sections_rpt, 'section_id,course_id,name,status,start_date,end_date');
         END IF;

         INSERT INTO mgccop.canvas_sections
              VALUES (r_section.banner_term,
                      r_section.banner_crn,
                      r_section.banner_section_id,
                      r_section.banner_short_name,
                      r_section.banner_long_name,
                      r_section.banner_account_id,
                      r_section.banner_status,
                      r_section.banner_start_date,
                      r_section.banner_end_date,
                      bstamp_in,
                      bstamp_in);

         UTL_FILE.put_line (
            csv_courses_rpt,
               r_section.banner_section_id
            || ','
            || '"'
            || r_section.banner_short_name
            || '",'
            || '"'
            || r_section.banner_long_name
            || '",'
            || r_section.banner_account_id
            || ','
            || r_section.banner_term
            || ','
            || r_section.banner_status
            || ','
            || TO_CHAR (r_section.banner_start_date, 'YYYY-MM-DD HH24:MI:SS')
            || '-06:00'
            || ','
            || TO_CHAR (r_section.banner_end_date, 'YYYY-MM-DD HH24:MI:SS')
            || '-06:00');

         UTL_FILE.put_line (
            csv_sections_rpt,
               r_section.banner_section_id
            || ','
            || r_section.banner_section_id
            || ','
            || '"'
            || r_section.banner_long_name
            || '",'
            || r_section.banner_status
            || ','
            || TO_CHAR (r_section.banner_start_date, 'YYYY-MM-DD HH24:MI:SS')
            || '-06:00'
            || ','
            || TO_CHAR (r_section.banner_end_date, 'YYYY-MM-DD HH24:MI:SS')
            || '-06:00');
      END LOOP;

      COMMIT;

      IF v_row > 0
      THEN
         UTL_FILE.fclose (csv_courses_rpt);
         UTL_FILE.fclose (csv_sections_rpt);
      END IF;
   END p_term_sections;

    /*Generate csv for new, deleted, or changed enrollments.
     *This generates a file for use in incremental uploads*/
   PROCEDURE p_get_enrollments (bstamp_in IN VARCHAR2, fpath_in IN VARCHAR2)
   IS
      csv_name   VARCHAR2 (70);
      csv_rpt    UTL_FILE.FILE_TYPE;
      bstamp     VARCHAR2 (12);
      v_row      NUMBER;

      CURSOR c_enrls
      IS
         SELECT * FROM mgccop.v_canvas_enrl;
   BEGIN
      csv_name := 'enrls_' || bstamp_in || '.csv';
      v_row := 0;

      FOR r_enrl IN c_enrls
      LOOP
         v_row := c_enrls%ROWCOUNT;

         IF c_enrls%ROWCOUNT = 1
         THEN
            csv_rpt := UTL_FILE.FOPEN (fpath_in, csv_name, 'w');
            UTL_FILE.put_line (csv_rpt, 'user_id,role,section_id,status');
         END IF;

         IF r_enrl.batch_status IS NULL AND r_enrl.banner_status = 'active'
         THEN
            INSERT INTO mgccop.canvas_enrl
                 VALUES (r_enrl.banner_term,
                         r_enrl.banner_crn,
                         r_enrl.banner_pidm,
                         r_enrl.banner_section_id,
                         r_enrl.banner_role,
                         r_enrl.banner_status,
                         bstamp_in,
                         bstamp_in,
                         r_enrl.banner_id);

            UTL_FILE.put_line (
               csv_rpt,
                  '211.'
               || r_enrl.banner_id
               || ','
               || r_enrl.banner_role
               || ','
               || r_enrl.banner_section_id
               || ','
               || r_enrl.banner_status);
         ELSIF r_enrl.batch_status = 'active' AND r_enrl.banner_status IS NULL
         THEN
            DELETE FROM mgccop.canvas_enrl
                  WHERE     enrl_term = r_enrl.batch_term
                        AND enrl_crn = r_enrl.batch_crn
                        AND enrl_pidm = r_enrl.batch_pidm
                        AND enrl_role = r_enrl.batch_role;

            UTL_FILE.put_line (
               csv_rpt,
                  '211.'
               || r_enrl.batch_id
               || ','
               || r_enrl.batch_role
               || ','
               || r_enrl.batch_section_id
               || ','
               || 'deleted');
         END IF;
      END LOOP;

      COMMIT;

      IF v_row > 0
      THEN
         UTL_FILE.fclose (csv_rpt);
      END IF;
   END p_get_enrollments;

   /*Generate csv for all enrollments for the specified term.
    *This generates a file for use in batch uploads.
    *Since enrollments are term-specific
    *batch mode uploads can be done. */
   PROCEDURE p_term_enrollments (term_in IN VARCHAR2, bstamp_in IN VARCHAR2, fpath_in IN VARCHAR2)
   IS
      csv_name   VARCHAR2 (70);
      csv_rpt    UTL_FILE.FILE_TYPE;
      bstamp     VARCHAR2 (12);
      v_row      NUMBER;

      CURSOR c_enrls
      IS
         SELECT *
           FROM mgccop.v_canvas_enrl
          WHERE banner_term = term_in;
   BEGIN
      csv_name := 'enrls_' || bstamp_in || '.csv';
      v_row := 0;

      FOR r_enrl IN c_enrls
      LOOP
         v_row := c_enrls%ROWCOUNT;

         IF c_enrls%ROWCOUNT = 1
         THEN
            csv_rpt := UTL_FILE.FOPEN (fpath_in, csv_name, 'w');
            UTL_FILE.put_line (csv_rpt, 'user_id,role,section_id,status');
         END IF;

         INSERT INTO mgccop.canvas_enrl
              VALUES (r_enrl.banner_term,
                      r_enrl.banner_crn,
                      r_enrl.banner_pidm,
                      r_enrl.banner_section_id,
                      r_enrl.banner_role,
                      r_enrl.banner_status,
                      bstamp_in,
                      bstamp_in,
                      r_enrl.banner_id);

         UTL_FILE.put_line (
            csv_rpt,
               '211.'
            || r_enrl.banner_id
            || ','
            || r_enrl.banner_role
            || ','
            || r_enrl.banner_section_id
            || ','
            || r_enrl.banner_status);
      END LOOP;

      IF v_row > 0
      THEN
         UTL_FILE.fclose (csv_rpt);
      END IF;
   END p_term_enrollments;

   /*Utilizes the call spec for general-purpose Java procedure for OS commands
    *to zip all csv files in the given filepath having the given batch stamp in the filename*/
   PROCEDURE p_zip_batch (bstamp_in IN VARCHAR2, fpath_in IN VARCHAR2)
   IS
   BEGIN
      --dbms_output.put_line('/d07/production/canvas/bin/zip -m -j '||fpath_in||'/'||bstamp_in||'.zip '||fpath_in||'/*'||bstamp_in||'.csv');
      mgccop.utlcmd.execute (
            '/d07/production/canvas/bin/zip -m -j '
         || fpath_in
         || '/'
         || bstamp_in
         || '.zip '
         || fpath_in
         || '/*'
         || bstamp_in
         || '.csv');
   END;

   /*Utilizes UTL_HTTP to create a POST request containing the raw zip data.
    *If a batch term is specified, the url parameters for a bach mode upload will be sent*/
   PROCEDURE p_upload (bstamp_in IN VARCHAR2, fpath_in IN VARCHAR2, batch_term_in IN VARCHAR2 DEFAULT NULL)
   IS
      creq               UTL_HTTP.req;
      cresp              UTL_HTTP.resp;
      upload_url         VARCHAR2 (500);
      buf                VARCHAR2 (32767);
      v_directory_name   VARCHAR2 (100);
      v_file_name        VARCHAR2 (100);
      v_line             VARCHAR2 (1000);
      v_file_handle      UTL_FILE.file_type;
      ex                 BOOLEAN;
      flen               NUMBER;
      bsize              NUMBER;
      file_buf           RAW (16384);
      file_buf_len       NUMBER := 16384;
   BEGIN
      v_directory_name := fpath_in;
      v_file_name := bstamp_in || '.zip';
      v_file_handle :=
         UTL_FILE.fopen (v_directory_name,
                         v_file_name,
                         'r',
                         16384);
      UTL_FILE.fgetattr (v_directory_name,
                         v_file_name,
                         ex,
                         flen,
                         bsize);
      UTL_HTTP.set_wallet (PATH => 'file:' || wallet_path, password => wallet_pass);

      --Determine if this is an incremental or batch upload, and set the appropriate url and parameters.
      IF batch_term_in IS NULL
      THEN
         upload_url :=
            'https://mgccc.instructure.com/api/v1/accounts/11/sis_imports.json?import_type=instructure_csv&'
            || 'extension=zip';
      ELSE
         upload_url :=
               'https://mgccc.instructure.com/api/v1/accounts/11/sis_imports.json?import_type=instructure_csv&'
            || 'extension=zip&'
            || 'batch_mode=1&'
            || 'batch_mode_term_id=sis_term_id:'
            || batch_term_in;
         DBMS_OUTPUT.put_line (upload_url);
      END IF;


      creq := UTL_HTTP.begin_request (upload_url, 'POST', 'HTTP/1.1');
      UTL_HTTP.set_header (creq, 'Content-Type', 'application/octet-stream');
      UTL_HTTP.set_header (creq, 'Authorization', 'Bearer ' || inst_token);
      UTL_HTTP.set_header (creq, 'Content-Length', flen);
      UTL_HTTP.set_header (creq, 'Expect', '100-continue');

      BEGIN
         LOOP
            IF flen - UTL_FILE.fgetpos (v_file_handle) < file_buf_len
            THEN
               file_buf_len := flen - UTL_FILE.fgetpos (v_file_handle);
            END IF;

            UTL_FILE.get_raw (v_file_handle, file_buf, file_buf_len);
            UTL_HTTP.write_raw (creq, file_buf);
            EXIT WHEN UTL_FILE.fgetpos (v_file_handle) >= flen;
         END LOOP;
      EXCEPTION
         WHEN UTL_HTTP.TOO_MANY_REQUESTS
         THEN
            UTL_HTTP.END_RESPONSE (cresp);
         WHEN NO_DATA_FOUND
         THEN
            NULL;
      END;

      cresp := UTL_HTTP.get_response (creq);
      UTL_HTTP.read_text (cresp, buf);
      DBMS_OUTPUT.put_line (buf);
      UTL_HTTP.end_response (cresp);
      UTL_FILE.fclose_all;
   END p_upload;

   /* Generate the csv files, zip them, and upload. 
    * Check for unoffered courses starting soon or recently and publish*/
   PROCEDURE p_inc_load (fpath_in IN VARCHAR2)
   IS
      bstamp   VARCHAR2 (20);
   BEGIN
      bstamp := TO_CHAR (SYSDATE, 'YYYYMMDDHH24SS');
      p_get_terms (bstamp, fpath_in);
      p_get_accounts (bstamp, fpath_in);
      p_get_users (bstamp, fpath_in);
      p_get_sections (bstamp, fpath_in);
      p_get_enrollments (bstamp, fpath_in);

      p_zip_batch (bstamp, fpath_in);

      p_upload (bstamp, fpath_in);

      p_offer_upcoming;
   END p_inc_load;

   /*Generate full files for all non term-specific data and upload.
    *Then generate term-specific files for each currently active term
    * and upload in batch mode per term.  Traditional terms include enrollments.
    * MSVCC terms get enrollments from ET, and should not have enrollments batched*/
   PROCEDURE p_batch_load (fpath_in IN VARCHAR2)
   IS
      bstamp   VARCHAR2 (50);

      CURSOR c_terms
      IS
         SELECT * FROM mgccop.v_canvas_terms;
   BEGIN
      --batch all non-term specific stuff to make sure we're up to date
      bstamp := TO_CHAR (SYSDATE, 'YYYYMMDDHH24SS') || '_pre_batch';
      p_get_terms (bstamp, fpath_in);
      p_all_accounts (bstamp, fpath_in);
      p_all_users (bstamp, fpath_in);
      p_zip_batch (bstamp, fpath_in);
      p_upload (bstamp, fpath_in);

      FOR r_term IN c_terms
      LOOP
         --generate traditional term courses/sections batch files
         bstamp := r_term.cterm_code || '_' || TO_CHAR (SYSDATE, 'YYYYMMDDHH24SS') || '_batch';

         BEGIN
            DELETE FROM mgccop.canvas_sections
                  WHERE section_term = r_term.cterm_code;
         END;

         COMMIT;
         p_term_sections (r_term.cterm_code, bstamp, fpath_in);

         --generate traditional term enrollment batch files
         BEGIN
            DELETE FROM mgccop.canvas_enrl
                  WHERE enrl_term = r_term.cterm_code;
         END;

         COMMIT;
         p_term_enrollments (r_term.cterm_code, bstamp, fpath_in);

         --Zip and batch to traditional term
         p_zip_batch (bstamp, fpath_in);
         p_upload (bstamp, fpath_in, r_term.cterm_code);
         --p_upload_test(bstamp, fpath_in,r_term.cterm_code);

         --generate MSVCC term courses/sections batch files
         bstamp := r_term.cterm_mccbterm || '_' || TO_CHAR (SYSDATE, 'YYYYMMDDHH24SS') || '_batch';

         BEGIN
            DELETE FROM mgccop.canvas_sections
                  WHERE section_term = r_term.cterm_mccbterm;
         END;

         COMMIT;
         p_term_sections (r_term.cterm_mccbterm, bstamp, fpath_in);

         --Zip and batch to MSVCC term
         p_zip_batch (bstamp, fpath_in);
         p_upload (bstamp, fpath_in, r_term.cterm_mccbterm);
      --p_upload_test(bstamp, fpath_in,r_term.cterm_mccbterm);

      END LOOP;
   END p_batch_load;
END canvas;
/