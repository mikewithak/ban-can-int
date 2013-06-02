DROP VIEW MGCCOP.V_CANVAS_ACCOUNTS;

/*View for sub-accounts.  Builds a heirarchy of accounts as:
 * DEPARTMENT -
 *           CAMPUS -         
 *                   SUBJECT
 * Canvas is sensitive to the order in which these appear in the file*/
CREATE OR REPLACE FORCE VIEW MGCCOP.V_CANVAS_ACCOUNTS
(
   BANNER_ACCOUNT_ID,
   BATCH_ACCOUNT_ID,
   BANNER_ACCOUNT_NAME,
   BATCH_ACCOUNT_NAME,
   BANNER_PARENT_ID,
   BATCH_PARENT_ID,
   BANNER_STATUS,
   BATCH_STATUS
)
AS
   SELECT a.account_id banner_account_id,
          b.account_id batch_account_id,
          a.account_name banner_account_name,
          b.account_name batch_account_name,
          a.account_parent_id banner_parent_id,
          b.account_parent_id batch_parent_id,
          a.account_status banner_status,
          b.account_status batch_status
     FROM    (SELECT 1 sorter,
                     dept_acct_id || '.1' ACCOUNT_ID,
                     dept_name ACCOUNT_NAME,
                     NULL ACCOUNT_PARENT_ID,
                     'active' ACCOUNT_STATUS
                FROM mgccop.canvas_depts
              UNION
              SELECT 2,
                     stvcamp_code || dept_acct_id || '.1',
                     stvcamp_desc,
                     dept_acct_id || '.1',
                     'active'
                FROM stvcamp,
                     mgccop.canvas_depts,
                     ssbsect,
                     mgccop.v_canvas_terms,
                     mgccop.canvas_dept_subj
               WHERE     stvcamp_code IN ('2', '3', '4', '5', '6', '7', '8')
                     AND ssbsect_term_code = cterm_code
                     AND ssbsect_ssts_code = 'A'
                     AND ssbsect_subj_code != 'VET'
                     AND ssbsect_subj_code = subj_code
                     AND subj_dept = dept_acct_id
                     AND ssbsect_camp_code = stvcamp_code
                     AND NOT (ssbsect_schd_code = 'O'
                              AND ssbsect_camp_code = '7')
              UNION
              SELECT 3,
                     stvcamp_code || stvsubj_code || '.1',
                     stvsubj_desc || ' (' || stvsubj_code || ')',
                     stvcamp_code || dept_acct_id || '.1',
                     'active'
                FROM stvcamp,
                     stvsubj,
                     mgccop.canvas_depts,
                     ssbsect,
                     mgccop.v_canvas_terms,
                     mgccop.canvas_dept_subj
               WHERE     stvcamp_code IN ('2', '3', '4', '5', '6', '7', '8')
                     AND ssbsect_term_code = cterm_code
                     AND ssbsect_ssts_code = 'A'
                     AND ssbsect_subj_code != 'VET'
                     AND ssbsect_subj_code = stvsubj_code
                     AND ssbsect_subj_code = subj_code
                     AND subj_dept = dept_acct_id
                     AND ssbsect_camp_code = stvcamp_code
                     AND NOT (ssbsect_schd_code = 'O'
                              AND ssbsect_camp_code = '7')
              ORDER BY 1) a
          FULL OUTER JOIN
             mgccop.canvas_accounts b
          ON (b.account_id = a.account_id);
		  
DROP VIEW MGCCOP.V_CANVAS_ENRL;

/* Full set of active banner enrollments and previously batched enrollments*/
CREATE OR REPLACE FORCE VIEW MGCCOP.V_CANVAS_ENRL
(
   BANNER_TERM,
   BATCH_TERM,
   BANNER_PIDM,
   BATCH_PIDM,
   BANNER_ID,
   BATCH_ID,
   BANNER_CRN,
   BATCH_CRN,
   BANNER_SECTION_ID,
   BATCH_SECTION_ID,
   BANNER_ROLE,
   BATCH_ROLE,
   BANNER_STATUS,
   BATCH_STATUS,
   BATCH_INITIAL,
   BATCH_LAST
)
AS
   SELECT banner.TERM banner_term,
          enrl_term batch_term,
          banner.PIDM banner_pidm,
          enrl_pidm batch_pidm,
          banner.id banner_id,
          enrl_id batch_id,
          banner.crn banner_crn,
          enrl_crn batch_crn,
          banner.section_id banner_section_id,
          enrl_section_id batch_section_id,
          banner.role banner_role,
          enrl_role batch_role,
          banner.status banner_status,
          enrl_status batch_status,
          enrl_initial_batch_id batch_initial,
          enrl_last_batch_id batch_last
     FROM    (
                   --STUDENTS
                   SELECT benrl.cterm TERM,
                     benrl.pidm PIDM,
                     benrl.crn CRN,
                     spriden_id ID,
                     benrl.role ROLE,
                     '211.' || benrl.CTERM || '.' || benrl.crn SECTION_ID,
                     benrl.status STATUS
                FROM (SELECT CASE
                                WHEN ssbsect_schd_code = 'O'
                                     AND ssbsect_ptrm_code != '2'
                                THEN
                                   cterm_mccbterm
                                ELSE
                                   cterm_code
                             END
                                CTERM,  --MCCB style term for non-flex online, otherwise MGCCC style
                             ssbsect_term_Code BTERM,
                             sfrstcr_pidm PIDM,
                             sfrstcr_crn CRN,
                             'student' ROLE,
                             'active' status
                        FROM mgccop.v_canvas_terms,
                             ssbsect,
                             stvrsts,
                             sfrstcr
                       WHERE     sfrstcr_term_code = cterm_code
                             AND sfrstcr_rsts_code = stvrsts_code
                             AND sfrstcr_term_code = ssbsect_term_code
                             AND sfrstcr_crn = ssbsect_crn
                             --Enrollments are pulled from Banner as active for 14 days
                             --prior to the first day of the class, and 14 following the last day
                             AND SYSDATE BETWEEN (ssbsect_ptrm_start_date
                                                  - 14)
                                             AND (ssbsect_ptrm_end_date + 14)
                             AND ssbsect_ssts_code = 'A'
                             AND ssbsect_subj_code != 'VET'
                             --Only Traditional and Flex Online student enrollments
                             AND (ssbsect_schd_code != 'O'
                                  OR ssbsect_ptrm_code = '2')
                             AND stvrsts_incl_sect_enrl = 'Y'
                      UNION
                      --INSTRUCTORS
                      SELECT CASE
                                WHEN ssbsect_schd_code = 'O'
                                     AND ssbsect_ptrm_code != '2'
                                THEN
                                   cterm_mccbterm
                                ELSE
                                   cterm_code
                             END
                                CTERM, --MCCB style term for non-flex online, otherwise MGCCC style
                             ssbsect_term_Code BTERM,
                             sirasgn_pidm PIDM,
                             sirasgn_crn CRN,
                             'teacher' ROLE,
                             'active' status
                        FROM sirasgn, ssbsect, mgccop.v_canvas_terms
                       WHERE     sirasgn_term_code = cterm_code
                             AND ssbsect_ssts_code = 'A'
                             AND ssbsect_subj_code != 'VET'
                             AND sirasgn_term_code = ssbsect_term_code
                             AND sirasgn_crn = ssbsect_crn) benrl,
                     spriden,
                     mgccop.canvas_sections,
                     mgccop.canvas_users,
                     mgccop.v_canvas_terms
               WHERE     spriden_pidm = benrl.pidm
                     AND spriden_change_ind IS NULL
                     AND spriden_id NOT LIKE 'OL%' --Exclude Away Instructors
                     AND spriden_id != 'M10001584' --Exclude "Staff" Instructor
                     AND section_term = benrl.cterm
                     AND section_crn = benrl.crn
                     AND user_pidm = benrl.pidm
                     AND cterm_code = benrl.bterm) banner
          FULL OUTER JOIN
             mgccop.canvas_enrl
          ON (    banner.term = enrl_term
              AND banner.crn = enrl_crn
              AND banner.pidm = enrl_pidm
              AND banner.role = enrl_role)
    WHERE enrl_term IS NULL
          OR enrl_term IN (SELECT cterm_code FROM mgccop.v_canvas_terms
                           UNION
                           SELECT cterm_mccbterm FROM mgccop.v_canvas_terms);
						   
DROP VIEW MGCCOP.V_CANVAS_SECTIONS;

/* Full set of active Banner Sections and Batched sections */
CREATE OR REPLACE FORCE VIEW MGCCOP.V_CANVAS_SECTIONS
(
   BANNER_TERM,
   BATCH_TERM,
   BANNER_CRN,
   BATCH_CRN,
   BANNER_SECTION_ID,
   BATCH_SECTION_ID,
   BANNER_SHORT_NAME,
   BATCH_SNAME,
   BANNER_LONG_NAME,
   BATCH_LONG_NAME,
   BANNER_ACCOUNT_ID,
   BATCH_ACCOUNT_ID,
   BANNER_STATUS,
   BATCH_STATUS,
   BANNER_START_DATE,
   BATCH_START_DATE,
   BANNER_END_DATE,
   BATCH_END_DATE,
   INITIAL_BATCH,
   LAST_BATCH
)
AS
   SELECT banner.term banner_term,
          section_term BATCH_TERM,
          banner.crn BANNER_CRN,
          section_crn BATCH_CRN,
          banner.bsection_id BANNER_SECTION_ID,
          section_id BATCH_SECTION_ID,
          banner.short_name BANNER_SHORT_NAME,
          section_sname BATCH_SNAME,
          banner.long_name BANNER_LONG_NAME,
          section_lname BATCH_LONG_NAME,
          banner.account_id BANNER_ACCOUNT_ID,
          section_account BATCH_ACCOUNT_ID,
          banner.status BANNER_STATUS,
          section_status BATCH_STATUS,
          banner.start_date BANNER_START_DATE,
          section_sdate BATCH_START_DATE,
          banner.end_date BANNER_END_DATE,
          section_edate BATCH_END_DATE,
          section_initial_batch_id INITIAL_BATCH,
          section_last_batch_id LAST_BATCH
     FROM    (SELECT CASE
                        WHEN ssbsect_schd_code = 'O'
                             AND ssbsect_ptrm_code != '2'
                        THEN
                           cterm_mccbterm
                        ELSE
                           cterm_code
                     END
                        term,  --MCCB style term for non-flex online, otherwise MGCCC style
                     ssbsect_crn crn,
                     '211.'
                     || CASE
                           WHEN ssbsect_schd_code = 'O'
                                AND ssbsect_ptrm_code != '2'
                           THEN
                              cterm_mccbterm
                           ELSE
                              cterm_code
                        END
                     || '.'
                     || ssbsect_crn
                        bsection_id,
                     DECODE (
                        ssbsect_schd_code,
                        'O',    ssbsect_subj_code
                             || ' '
                             || ssbsect_crse_numb
                             || ' '
                             || ssbsect_seq_numb
                             || ' '
                             || '(Online)',
                           ssbsect_subj_code
                        || ' '
                        || ssbsect_crse_numb
                        || ' '
                        || ssbsect_seq_numb)
                        AS short_name,  
                     cterm_code || ' '
                     || DECODE (
                           ssbsect_schd_code,
                           'O',    ssbsect_subj_code
                                || ' '
                                || ssbsect_crse_numb
                                || ' '
                                || ssbsect_seq_numb
                                || ' '
                                || A.scbcrse_title
                                || ' '
                                || '(Online)',
                              ssbsect_subj_code
                           || ' '
                           || ssbsect_crse_numb
                           || ' '
                           || ssbsect_seq_numb
                           || ' '
                           || A.scbcrse_title)
                        AS long_name,
                     ssbsect_camp_code || ssbsect_subj_code || '.1'
                        AS account_id,  --All courses are attached to the bottom-level "subject" node sub-account
                     'active' status,
                     ssbsect_ptrm_start_date start_date,
                     ssbsect_ptrm_end_date end_date
                FROM ssbsect
                     JOIN mgccop.v_canvas_terms
                        ON (ssbsect_term_code = cterm_code)
                     JOIN scbcrse A
                        ON (A.scbcrse_subj_code = ssbsect_subj_code
                            AND A.scbcrse_crse_numb = ssbsect_crse_numb)
               WHERE ssbsect_ssts_code = 'A' AND ssbsect_subj_code != 'VET'
                     AND A.scbcrse_eff_term =
                            (SELECT MAX (B.scbcrse_eff_term)
                               FROM scbcrse B
                              WHERE B.scbcrse_subj_code = A.scbcrse_subj_code
                                    AND B.scbcrse_crse_numb =
                                           A.scbcrse_crse_numb
                                    AND B.scbcrse_eff_term <=
                                           ssbsect_term_code)
                     AND NOT (ssbsect_schd_code = 'O'
                              AND ssbsect_camp_code = '7')) banner
          FULL OUTER JOIN
             mgccop.canvas_sections
          ON (banner.term = section_term AND banner.crn = section_crn)
    WHERE section_term IS NULL
          OR section_term IN
                (SELECT cterm_code FROM mgccop.v_canvas_terms
                 UNION
                 SELECT cterm_mccbterm FROM mgccop.v_canvas_terms);
				 
DROP VIEW MGCCOP.V_CANVAS_TERMS;

/* Currently active terms */
CREATE OR REPLACE FORCE VIEW MGCCOP.V_CANVAS_TERMS
(
   CTERM_CODE,
   CTERM_DESC,
   CTERM_TSTART,
   CTERM_TEND,
   CTERM_OSTART,
   CTERM_OEND,
   CTERM_MCCBTERM
)
AS
   SELECT stvterm_code cterm_code,
          stvterm_desc cterm_desc,
          sobptrm_start_date tterm_start,
          sobptrm_end_date tterm_end,
          (SELECT sobptrm_start_date
             FROM sobptrm
            WHERE sobptrm_term_code = stvterm_code
                  AND sobptrm_ptrm_code = 'O')
             oterm_start,
          (SELECT sobptrm_end_date
             FROM sobptrm
            WHERE sobptrm_term_code = stvterm_code
                  AND sobptrm_ptrm_code = 'O')
             oterm_end,
          CASE
             WHEN SUBSTR (stvterm_code, 5, 2) = '40'
             THEN
                NULL
             ELSE
                DECODE (SUBSTR (stvterm_code, 5, 2),
                        '10', SUBSTR (stvterm_code, 1, 4),
                        SUBSTR (stvterm_code, 1, 4) + 1)
                || DECODE (SUBSTR (stvterm_code, 5, 2),
                           '20', '1',
                           '30', '2',
                           '40', '2',
                           '10', '3')
          END
             cterm_mccbterm
     FROM stvterm, sobptrm
    WHERE     SUBSTR (stvterm_code, 5, 2) IN ('10', '20', '30', '40')
          AND sobptrm_term_code = stvterm_code
          AND sobptrm_ptrm_code = '1'
          AND ( (SYSDATE BETWEEN (sobptrm_start_date - 90)  --Term becomes active 90 days prior to start date
                             AND (stvterm_end_date + 15))  --Term remains active for 15 days after end date
               OR (stvterm_code IN
                      (SELECT add_term FROM mgccop.canvas_add_terms)))
          AND stvterm_code NOT IN
                 (SELECT excl_term FROM mgccop.canvas_excl_terms);
				 
				 
DROP VIEW MGCCOP.V_CANVAS_USERS;

/* Full set of student, faculty, and employee users*/
CREATE OR REPLACE FORCE VIEW MGCCOP.V_CANVAS_USERS
(
   BANNER_PIDM,
   BATCH_PIDM,
   BANNER_ID,
   BATCH_ID,
   BANNER_LNAME,
   BATCH_LNAME,
   BANNER_FNAME,
   BATCH_FNAME,
   BANNER_PASSWORD,
   BATCH_PASSWORD,
   BANNER_EMAIL,
   BATCH_EMAIL,
   BATCH_STATUS,
   INITIAL_BATCH,
   LAST_BATCH
)
AS
   --STUDENTS
   SELECT banner.pidm banner_pidm,
          user_pidm batch_pidm,
          banner.id banner_id,
          user_id batch_id,
          banner.last_name banner_lname,
          user_lname batch_lname,
          banner.first_name banner_fname,
          user_fname batch_fname,
          mgccop.canvas.f_get_canvas_pwd (banner.pidm) banner_password,
          user_password batch_password,
          mgccop.canvas.f_get_canvas_email (banner.pidm) banner_email,
          user_email batch_email,
          user_status batch_status,
          user_initial_batch_id initial_batch,
          user_last_batch_id last_batch
     FROM (SELECT spriden_pidm PIDM,
                  spriden_id ID,
                  spriden_last_name LAST_NAME,
                  spriden_first_name FIRST_NAME
             FROM (SELECT sfbetrm_pidm PIDM
                     FROM sfbetrm
                    WHERE sfbetrm_term_code IN
                             (SELECT cterm_code FROM mgccop.v_canvas_terms)
                          AND EXISTS
                                 (SELECT 1
                                    FROM sfrstcr
                                   WHERE sfrstcr_rsts_code IN
                                            ('RE', 'RI', 'RW', 'AU')
                                         AND sfrstcr_term_code =
                                                sfbetrm_term_code
                                         AND sfrstcr_pidm = sfbetrm_pidm)
                   UNION
                   --FACULTY
                   SELECT sirasgn_pidm PIDM
                     FROM sirasgn, ssbsect
                    WHERE sirasgn_term_code IN
                             (SELECT cterm_code FROM mgccop.v_canvas_terms)
                          AND sirasgn_term_code = ssbsect_term_code
                          AND sirasgn_crn = ssbsect_crn
                          AND ssbsect_ssts_code = 'A'
                   --AND ssbsect_enrl > 0
                   UNION
                   --EMPLOYEES
                   SELECT pebempl_pidm PIDM
                     FROM pebempl
                    WHERE pebempl_empl_status = 'A'
                          AND EXISTS
                                 (SELECT 1
                                    FROM nbrbjob, nbrjobs a
                                   WHERE nbrbjob_pidm = pebempl_pidm
                                         AND SYSDATE BETWEEN nbrbjob_begin_date
                                                         AND NVL (
                                                                nbrbjob_end_date,
                                                                '01-JAN-2999')
                                         AND nbrbjob_contract_type = 'P'
                                         AND nbrbjob_pidm = a.nbrjobs_pidm
                                         AND nbrbjob_posn = a.nbrjobs_posn
                                         AND nbrbjob_suff = a.nbrjobs_suff
                                         AND nbrbjob_pidm = pebempl_pidm
                                         AND a.nbrjobs_status = 'A'
                                         AND a.nbrjobs_ecls_code NOT IN
                                                ('50', '51', 'BM')
                                         AND a.nbrjobs_effective_date =
                                                (SELECT MAX (
                                                           b.nbrjobs_effective_date)
                                                   FROM nbrjobs b
                                                  WHERE b.nbrjobs_pidm =
                                                           a.nbrjobs_pidm
                                                        AND b.nbrjobs_posn =
                                                               a.nbrjobs_posn
                                                        AND b.nbrjobs_suff =
                                                               a.nbrjobs_suff
                                                        AND b.nbrjobs_status =
                                                               'A'
                                                        AND b.nbrjobs_effective_date <=
                                                               SYSDATE))) banner_pidms,
                  spriden
            WHERE     spriden_pidm = banner_pidms.pidm
                  AND spriden_change_ind IS NULL
                  AND spriden_id NOT LIKE 'OL%'
                  AND spriden_id != 'M10001584') banner,
          mgccop.canvas_users
    WHERE banner.pidm = user_pidm(+);
				 

				 


