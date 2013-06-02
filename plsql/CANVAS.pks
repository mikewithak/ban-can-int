CREATE OR REPLACE PACKAGE MGCCOP.canvas AS

   FUNCTION f_get_canvas_email(pidm_in IN NUMBER) RETURN goremal.goremal_email_address%TYPE;
   
   FUNCTION f_get_canvas_pwd(pidm_in IN NUMBER) RETURN gorpaud.gorpaud_pin%TYPE;
   
   FUNCTION f_load_status (load_id IN VARCHAR2) RETURN VARCHAR2;
                                                     
   PROCEDURE p_upload (bstamp_in IN VARCHAR2,
                                         fpath_in IN VARCHAR2,
                                         batch_term_in IN VARCHAR2 DEFAULT NULL);
                                         
   PROCEDURE p_inc_load(fpath_in IN VARCHAR2);
  
   PROCEDURE p_batch_load(fpath_in IN VARCHAR2);
  
  
END canvas;
/