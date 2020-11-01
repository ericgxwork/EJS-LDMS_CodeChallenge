SET SERVEROUTPUT ON SIZE 999999
DECLARE
  --
  -- DBA Utility code to compile invalid objects against a DB
  -- To be used solely after applying release.
  -- $Revision:   1.5  $
  --
  TYPE t_objname IS TABLE of user_objects.object_name%TYPE INDEX BY BINARY_INTEGER;
  TYPE t_objtype IS TABLE of user_objects.object_type%TYPE INDEX BY BINARY_INTEGER;
  v_name t_objname;
  v_type t_objtype;
  --
  CURSOR cur_obj IS
    SELECT uo.object_name
          ,uo.object_type
    FROM   user_objects uo
    WHERE  uo.object_type IN ('FUNCTION','JAVA SOURCE','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')
    AND    uo.status = 'INVALID'
    ORDER BY DECODE(uo.object_name,'MSP_PRE_POLLING','1','MSP_POLLED_FILE_UPDATE','2','3'),uo.object_name;
  --
  pn_cnt  NUMBER(10):= 1;
  pn_loop NUMBER(10);
  pn_recs NUMBER(10);
  pn_i    NUMBER(2);
  --
PROCEDURE p_compile(pc_name IN VARCHAR2,pc_type IN VARCHAR2) IS
  --
  lc_expr VARCHAR2(400);
  lc_cmd  VARCHAR2(2000);
  ln_job  NUMBER;
  --
BEGIN
  --
  IF pc_type != 'PACKAGE BODY' THEN
    lc_expr := 'alter '||pc_type||' "'||pc_name||'" compile';
  ELSE
    lc_expr := 'alter PACKAGE "'||pc_name||'" compile BODY';
  END IF;
  --
  lc_cmd := 'DECLARE ln_chk NUMBER; CURSOR cur_chk_inv IS SELECT 1 FROM user_objects'
          ||' WHERE object_name = '''||pc_name||''' AND object_type = '''||pc_type||''' AND status = ''INVALID'';'
          ||' BEGIN OPEN cur_chk_inv; FETCH cur_chk_inv INTO ln_chk; IF cur_chk_inv%FOUND THEN'
          ||' EXECUTE IMMEDIATE '''||lc_expr||'''; END IF; CLOSE cur_chk_inv; EXCEPTION WHEN OTHERS THEN null; END;';
  --
  dbms_job.submit(ln_job,lc_cmd);
  COMMIT;
  --
END p_compile;
--
PROCEDURE p_chk_jobs IS
  --
  ln_cnt NUMBER := 1;
  --
  CURSOR cur_job IS
    SELECT COUNT(1)
    FROM   user_jobs uj
    WHERE  UPPER(uj.what) LIKE UPPER ('DECLARE ln_chk NUMBER; CURSOR cur_chk_inv IS SELECT 1 FROM user_objects%');
  --
BEGIN
  --
  LOOP
    OPEN cur_job;
    FETCH cur_job
    INTO  ln_cnt;
    CLOSE cur_job;
    IF ln_cnt = 0 THEN
      EXIT;
    END IF;
    dbms_lock.sleep(5);
  END LOOP;
  --
END p_chk_jobs;
--
BEGIN
  --
  FOR pn_i IN 1..2 LOOP
    --
    pn_cnt := 1;
    --
    FOR obj_rec IN cur_obj LOOP
      v_name(pn_cnt) := obj_rec.object_name;
      v_type(pn_cnt) := obj_rec.object_type;
      pn_cnt := pn_cnt + 1;
    END LOOP;
    --
    pn_recs := pn_cnt-1;
    IF pn_recs >= 1 THEN
      --
      FOR pn_loop IN 1..pn_recs LOOP
        IF v_name(pn_loop) != '@' THEN
          p_compile(v_name(pn_loop),v_type(pn_loop));
        END IF;
      END LOOP;
      --
      p_chk_jobs;
      --
    END IF;
    --
  END LOOP;
  --
  dbms_output.put_line('List of invalid objects....');
  FOR obj_rec IN cur_obj LOOP
    dbms_output.put_line(obj_rec.object_type||' '||obj_rec.object_name);
  END LOOP;
  --
END;
/ 

