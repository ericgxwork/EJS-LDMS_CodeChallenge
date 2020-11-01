PROMPT
PROMPT Applying package specification PKG_EMP_MAINTENANCE Version 1.0
PROMPT 
CREATE OR REPLACE PACKAGE EJS.pkg_employee_maintenance IS
  --
  -- ---------------------------------------------------------------------
  --
  -- PKG_EMP_MAINTENANCE
  -- PKG0001.SQL
  --
  -- Description: 
  -- Contains all database objects required for the maintenance and retrieval of employee records
  -- Important note: No COMMIT is done as part of this code this is left to higher level code  
  --
  -- $Revision$ 1.0
  -- $Date$     29.10.20
  -- $Author$   Eric Salles
  --
  -- Amendment records
  -- CR#         Who            When              Description
  --
  -- ---------------------------------------------------------------------
  --
  -- Status values
  gc_pass  CONSTANT VARCHAR2(1) := '1';
  gc_fail  CONSTANT VARCHAR2(1) := '0';
  --
  -- Message Level  
  gc_info    CONSTANT VARCHAR2(1) := 'I';
  gc_warning CONSTANT VARCHAR2(1) := 'W';
  gc_error   CONSTANT VARCHAR2(1) := 'E';
  gc_fatal   CONSTANT VARCHAR2(1) := 'F';
  --
  --
  gc_error_point VARCHAR2(100);  -- Allows progress of processing to be tracked if an issue occurs and should be unique across entire solution.
                                -- can be added to debug table with autonomous transactions 
  -- 
  -- ---------------------------------------
  -- p_create_employee
  -- Description: 
  -- Allow creation of new employees
  -- pto_employee_id  ==> A valid employee id if employee number is to be fixed. if set to Null use next sequence number    
  -- ptm_employee_name ==> The employee name   
  -- ptm_job_title     ==> The employee job title 
  -- pto_manager_id    ==> The manager of the employee being created 
  -- ptm_date_hired    ==> The date the employee is hired 
  -- ptm_salary        ==> The yearly salary 
  -- ptm_department_id ==> The department identifier the employee will be assigned to 
  --  
  PROCEDURE p_create_employee
  (  pto_employee_id    IN EMPLOYEES.EMPLOYEE_ID%TYPE    
    ,ptm_employee_name  IN EMPLOYEES.EMPLOYEE_NAME%TYPE  
    ,ptm_job_title      IN EMPLOYEES.JOB_TITLE%TYPE      
    ,pto_manager_id     IN EMPLOYEES.MANAGER_ID%TYPE     
    ,ptm_date_hired     IN EMPLOYEES.DATE_HIRED%TYPE     
    ,ptm_salary         IN EMPLOYEES.SALARY%TYPE         
    ,ptm_department_id  IN EMPLOYEES.DEPARTMENT_ID%TYPE  
	,pc_status        OUT VARCHAR2
	,pn_err_no        OUT NUMBER
	,pc_err_msg       OUT VARCHAR2
	,pc_err_lvl       OUT VARCHAR2
  );	
  --	
  -- ---------------------------------------  
  -- p_update_salary
  --
  -- Description: Allow maintenance of an employee salary using percentage passed in
  -- ptm_employee_id    => A valid employee Id
  -- pnm_percentage     => percentage (can be postive or negative) use to adjust the salary
  --
  PROCEDURE p_update_salary
  (  ptm_employee_id    IN EMPLOYEES.EMPLOYEE_ID%TYPE    
    ,pnm_percentage     IN  NUMBER         
	,pc_status         OUT VARCHAR2
	,pn_err_no         OUT NUMBER
	,pc_err_msg        OUT VARCHAR2
	,pc_err_lvl        OUT VARCHAR2	
  );  --	
  -- ---------------------------------------  
  -- p_transfer_employee
  --
  -- Description: 
  -- Allow an employee to be transferred to a new department
  -- ptm_employee_id       ==> A valid employee_id
  -- ptm_new_department_id ==> The new department the employee is moving to
  --
  PROCEDURE p_transfer_employee
  (  ptm_employee_id       IN EMPLOYEES.EMPLOYEE_ID%TYPE    
    ,ptm_new_department_id IN EMPLOYEES.DEPARTMENT_ID%TYPE
	,pc_status        OUT VARCHAR2
	,pn_err_no        OUT NUMBER
	,pc_err_msg       OUT VARCHAR2
	,pc_err_lvl       OUT VARCHAR2
  );	
  --	
  -- ---------------------------------------  
  -- f_get_emp_salary
  -- Description: 
  -- Returns employee yearly salary
  -- ptm_employee_id       ==> A valid employee_id
  --
  FUNCTION f_get_emp_salary
  ( ptm_employee_id       IN EMPLOYEES.EMPLOYEE_ID%TYPE ) RETURN NUMBER;
  --
  -- -------------------------------------------------------
  -- p_employee_report
  -- Produce employee reports in CSV formats
  -- pcm_report_type    ==> The type of report. Valid Values 'ALL_EMP_DEPT_REPORT' for all employyees in a department
  --                                                      'EMP_SAL_DEPT_REPORT' total salary per department
  -- ptm_department_id  ==> The department Id can to report on 
  -- pco_file_name      ==> The file name to be produced in extract folder 'EXTRACT_DIR' if none passed in defaulted to 
  --                        report_type + YYMMDDHH24MISS.csv 
  -- pco_file_separator ==> Defaulted to comma if none passed in
  --
  PROCEDURE p_employee_report( pcm_report_type IN VARCHAR2
                              ,ptm_department_id IN EMPLOYEES.DEPARTMENT_ID%TYPE
                              ,pco_file_name IN VARCHAR2
                              ,pco_column_separator IN VARCHAR2 DEFAULT ','
                           	  ,pc_status        OUT VARCHAR2
	                          ,pn_err_no        OUT NUMBER
	                          ,pc_err_msg       OUT VARCHAR2
	                          ,pc_err_lvl       OUT VARCHAR2
	                         );
END pkg_employee_maintenance;
/
PROMPT
PROMPT Applying package body PKG_EMP_MAINTENANCE Version 1.0
PROMPT 
CREATE OR REPLACE PACKAGE BODY pkg_employee_maintenance IS
  -- NOTE to Reviewer: 
  -- Error codes and messages typically would be stored in a separate table with its translation for multi-language support
  --
  -- Failure (50000 range)
  cn_employee_exists       CONSTANT NUMBER(9) := 50000;
  cc_employee_exists       CONSTANT VARCHAR2(100) := 'Employee already exists';
  cn_invalid_manager       CONSTANT NUMBER(9) := 50005;
  cc_invalid_manager       CONSTANT VARCHAR2(100) := 'Manager does not exist';
  cn_invalid_department    CONSTANT NUMBER(9) := 50010;
  cc_invalid_department    CONSTANT VARCHAR2(100) := 'Department does not exist';
  cn_invalid_salary        CONSTANT NUMBER(9) := 50015;
  cc_invalid_salary        CONSTANT VARCHAR2(100) := 'Salary must be greater or equal to 0';
  cn_invalid_employee      CONSTANT NUMBER(9) := 50020;
  cc_invalid_employee      CONSTANT VARCHAR2(100) := 'Employee does not exist';
  cn_record_locked         CONSTANT NUMBER(9) := 50025;
  cc_record_locked         CONSTANT VARCHAR2(100) := 'Record locked by another user';
  cn_file_operation_err    CONSTANT NUMBER(9) := 50030;
  cc_file_operation_err    CONSTANT VARCHAR2(100) := 'File operation error. Type:';
  cn_invalid_percentage    CONSTANT NUMBER(9) := 50035;
  cc_invalid_percentage    CONSTANT VARCHAR2(100) := 'Invalid value for salary adjustement percentage: ';
  -- Warning (30000)
  cn_already_in_department CONSTANT NUMBER(9) := 30000;
  cc_already_in_department CONSTANT VARCHAR2(100) := 'User is already in the department - No action taken';
  cn_invalid_rep_type      CONSTANT NUMBER(9) := 30005;
  cc_invalid_rep_type      CONSTANT VARCHAR2(100) := 'Invalid report type - No file produced';
  -- Information (10000 range)  
  cn_record_created        CONSTANT NUMBER(9) := 10000;
  cc_record_created        CONSTANT VARCHAR2(100) := 'Record created';
  cn_record_updated        CONSTANT NUMBER(9) := 10005;
  cc_record_updated        CONSTANT VARCHAR2(100) := 'Record updated';
  cn_report_created        CONSTANT NUMBER(9) := 10010;
  cc_report_created        CONSTANT VARCHAR2(100) := 'Repord created in extract folder. File Name is';
  --
  --Local functions and procs
  --      
  FUNCTION f_is_valid_emp_id  
  ( ptm_emp_id       IN EMPLOYEES.EMPLOYEE_ID%TYPE ) RETURN BOOLEAN IS
    --
    -- Description: Validate employee Id
    -- returns TRUE  if Employee exists
    --         FALSE if Employee does not exist
    --   
	lb_return BOOLEAN := TRUE;
	ln_dummy  NUMBER(1);
	--
	CURSOR cur_emps( it_emp_id EMPLOYEES.EMPLOYEE_ID%TYPE ) IS
	  SELECT 1
	  FROM   EMPLOYEES e
	  WHERE  e.EMPLOYEE_ID = it_emp_id;
	--  
  BEGIN
    --
	OPEN cur_emps( it_emp_id => ptm_emp_id );
	FETCH cur_emps INTO ln_dummy;
	IF ( cur_emps%NOTFOUND ) THEN  
	  --
	  -- Employee does not exist
	  --
	  lb_return := FALSE;
	  --
	END IF;
	CLOSE cur_emps;
	--
    RETURN( lb_return );	
	--
  END f_is_valid_emp_id;
  -- ---------------------------------------  
  FUNCTION f_is_valid_dept_id
  ( ptm_dept_id       IN DEPARTMENTS.DEPARTMENT_ID%TYPE ) RETURN BOOLEAN IS
    --
    -- Description: Validate department Id
    -- returns TRUE  if department exists
    --         FALSE if department does not exist
	lb_return BOOLEAN := TRUE;
	ln_dummy  NUMBER(1);
	--
	CURSOR cur_depts( it_dept_id EMPLOYEES.DEPARTMENT_ID%TYPE ) IS
	  SELECT 1
	  FROM   DEPARTMENTS d
	  WHERE  d.DEPARTMENT_ID = ptm_dept_id;
	--  
  BEGIN
    --
	OPEN cur_depts( it_dept_id => ptm_dept_id );
	FETCH cur_depts INTO ln_dummy;
	IF ( cur_depts%NOTFOUND ) THEN  
	  --
	  -- Department does not exist
	  --
	  lb_return := FALSE;
	  --
	END IF;
	CLOSE cur_depts;
	--
    RETURN( lb_return );	
	--
  END f_is_valid_dept_id;
  -- --------------------------------------
  FUNCTION f_is_valid_salary( ptm_salary IN EMPLOYEES.SALARY%TYPE ) RETURN BOOLEAN IS
  --
  -- Description:
  -- Validate Salary
  -- returns TRUE if >= 0 else FALSE
  --
  BEGIN
    -- 
    RETURN( CASE WHEN NVL(ptm_salary, -1) >= 0 
            THEN TRUE 
            ELSE FALSE 
            END 
          );
    --
  END;
  --          
  PROCEDURE p_create_employee
  (  pto_employee_id    IN EMPLOYEES.EMPLOYEE_ID%TYPE    
    ,ptm_employee_name  IN EMPLOYEES.EMPLOYEE_NAME%TYPE  
    ,ptm_job_title      IN EMPLOYEES.JOB_TITLE%TYPE      
    ,pto_manager_id     IN EMPLOYEES.MANAGER_ID%TYPE     
    ,ptm_date_hired     IN EMPLOYEES.DATE_HIRED%TYPE     
    ,ptm_salary         IN EMPLOYEES.SALARY%TYPE         
    ,ptm_department_id  IN EMPLOYEES.DEPARTMENT_ID%TYPE  
	,pc_status        OUT VARCHAR2
	,pn_err_no        OUT NUMBER
	,pc_err_msg       OUT VARCHAR2
	,pc_err_lvl       OUT VARCHAR2) IS
    -- 
    -- Description: 
    -- Allow creation of new employees
    -- pto_employee_id  ==> A valid employee id if employee number is to be fixed (can also be used to recreate rows). 
    --                      If set to Null use next sequence number    
    -- ptm_employee_name ==> The employee name   
    -- ptm_job_title     ==> The employee job title 
    -- pto_manager_id    ==> The manager of the employee being created 
    -- ptm_date_hired    ==> The date the employee is hired 
    -- ptm_salary        ==> The yearly salary 
    -- ptm_department_id ==> The department identifier the employee will be assigned to 
    --  
    lt_emp_id EMPLOYEES.EMPLOYEE_ID%TYPE;  
    --
	EX_INVALID_MANAGER EXCEPTION;
	EX_INVALID_DEPARTMENT EXCEPTION;
	EX_INVALID_SALARY EXCEPTION;
	--
  BEGIN
    --
    pc_status := gc_pass;
    --
    gc_error_point := 'PEMPCE0000';
    --
    -- If data quality is very poor validation could include mandatory columns being checked as passed in
    --    
    -- Validate key columns passed in mandatory columns where not checked will raise ORA-1400 with actual column name in 
    -- error message
    --
    --
    IF ( pto_employee_id IS NOT NULL
         AND f_is_valid_emp_id( ptm_emp_id => pto_employee_id ) )    
    THEN
      --
      -- Employee already was passed in but it already exists
      --
      gc_error_point := 'PEMPCE0015';
      --
      RAISE DUP_VAL_ON_INDEX;
      --
    ELSIF ( pto_manager_id IS NOT NULL
            AND NOT f_is_valid_emp_id( ptm_emp_id => pto_manager_id ) 
          ) 
    THEN
      --
      --
      gc_error_point := 'PEMPCE0020';
      --      
      RAISE EX_INVALID_MANAGER;
      --
    ELSIF ( ( ptm_department_id IS NOT NULL
              AND NOT f_is_valid_dept_id( ptm_dept_id => ptm_department_id )
            )
            OR
            ( ptm_department_id IS NULL 
            )            
          ) 
    THEN
      --
      gc_error_point := 'PEMPCE0025';
      --      
      RAISE EX_INVALID_DEPARTMENT;
      --
    ELSIF ( NOT f_is_valid_salary( ptm_salary => ptm_salary ) 
          ) 
    THEN
      --
      gc_error_point := 'PEMPCE0030';
      --      
      RAISE EX_INVALID_SALARY;
      --
    END IF;
    --
    -- Employee was not passed in so use sequence
    --
    lt_emp_id := NVL( pto_employee_id, seq_employee_id.NEXTVAL );
    --
    -- OK to add employee
    --          
    INSERT INTO EMPLOYEES
    ( EMPLOYEE_ID
     ,EMPLOYEE_NAME
     ,JOB_TITLE
     ,MANAGER_ID
     ,DATE_HIRED 
     ,SALARY  
     ,DEPARTMENT_ID
    ) 
    VALUES
    ( lt_emp_id    
     ,ptm_employee_name  
     ,ptm_job_title      
     ,pto_manager_id     
     ,ptm_date_hired     
     ,ptm_salary         
     ,ptm_department_id      
    );
    --
    -- NOTE may want to issue warning if top level manager already exists
    --      may want to issue warning if employee created is not in same department as its manager
    --         
    pn_err_no := cn_record_created;
    pc_err_msg := cc_record_created||' Employee ID:'||lt_emp_id;
    pc_err_lvl := gc_info; 
    --
    gc_error_point := 'PEMPCE9999';
    --
    EXCEPTION
      --
      WHEN DUP_VAL_ON_INDEX 
      THEN
        --
        -- Employee already exists
        --
        pc_status := gc_fail;
        pn_err_no := cn_employee_exists;
        pc_err_msg := cc_employee_exists;
        pc_err_lvl := gc_error; 
        --      
      WHEN EX_INVALID_MANAGER THEN
        --
        -- Manager Id does not exist
        --
        pc_status := gc_fail;
        pn_err_no := cn_invalid_manager;
        pc_err_msg := cc_invalid_manager;
        pc_err_lvl := gc_error; 
        --      
      WHEN EX_INVALID_DEPARTMENT THEN
        --
        -- Invalid department id passed in
        --
        pc_status := gc_fail;
        pn_err_no := cn_invalid_department;
        pc_err_msg := cc_invalid_department;
        pc_err_lvl := gc_error; 
        --      
      WHEN EX_INVALID_SALARY THEN
        --
        -- Invalid department id passed in
        --
        pc_status := gc_fail;
        pn_err_no := cn_invalid_salary;
        pc_err_msg := cc_invalid_salary;
        pc_err_lvl := gc_error; 
        --      
      WHEN OTHERS THEN
       --
       -- Fatal SQL errors
       --      
       pc_status := gc_fail;
       pn_err_no := SQLCODE;
       pc_err_msg := SQLERRM;
       pc_err_lvl := gc_fatal; 
       --
  END  p_create_employee; 	
  -- ---------------------------------------  
  PROCEDURE p_update_salary
  (  ptm_employee_id    IN EMPLOYEES.EMPLOYEE_ID%TYPE    
    ,pnm_percentage     IN  NUMBER         
	,pc_status         OUT VARCHAR2
	,pn_err_no         OUT NUMBER
	,pc_err_msg        OUT VARCHAR2
	,pc_err_lvl        OUT VARCHAR2	
   ) IS	
    --
    -- Description: 
    -- Allow maintenance of an employee salary using percentage passed in
    -- ptm_employee_id    => A valid employee Id
    -- pnm_percentage     => percentage (can be postive or negative) use to adjust the salary
    --
    lt_salary EMPLOYEES.SALARY%TYPE;
    --
    CURSOR cur_emp_lock( it_emp_id EMPLOYEES.EMPLOYEE_ID%TYPE ) IS
      SELECT e.SALARY
      FROM   EMPLOYEES e
      WHERE  e.EMPLOYEE_ID = it_emp_id
      FOR UPDATE OF e.SALARY NOWAIT;
    --    
	EX_INVALID_EMPLOYEE   EXCEPTION;
	EX_INVALID_SALARY     EXCEPTION;
	EX_INVALID_PERCENTAGE EXCEPTION;
	--
  BEGIN
    --
    -- Validate employee
    --
    --
    gc_error_point := 'PEMPUS0000';
    --
    IF ( NVL( pnm_percentage, 1 ) < -100 ) THEN
      --
      -- Percentage must be entered and be greater than -100% 
      --
      RAISE EX_INVALID_PERCENTAGE;
      --
    ELSIF ( ptm_employee_id IS NULL
         OR 
         NOT f_is_valid_emp_id( ptm_emp_id => ptm_employee_id ) )    
    THEN
      --
      -- Not a valid employee
      --
      gc_error_point := 'PEMPUS0005';
      --
      RAISE EX_INVALID_EMPLOYEE;
      --
    END IF;
    --
    --
    -- Valid employee so lock it
    --
    gc_error_point := 'PEMPUS0010';
    --
    OPEN cur_emp_lock( it_emp_id => ptm_employee_id );
    FETCH cur_emp_lock INTO lt_salary;
    IF ( cur_emp_lock%FOUND ) THEN
      --
      gc_error_point := 'PEMPUS0015';
      --    
      --
      -- Calculate new salary and validate it
      --
      lt_salary := lt_salary + ( lt_salary * pnm_percentage / 100 );
      --
      IF ( f_is_valid_salary( ptm_salary => lt_salary ) ) THEN
        --
        gc_error_point := 'PEMPUS0020';
        --
        UPDATE EMPLOYEES
        SET SALARY = lt_salary
        WHERE CURRENT OF cur_emp_lock;
        --
        CLOSE  cur_emp_lock;
        --
        pc_status := gc_pass;
        pn_err_no := cn_record_updated;
        pc_err_msg := cc_record_updated;
        pc_err_lvl := gc_info;
        --
      ELSE
        --
        gc_error_point := 'PEMPUS0025';
        --
        CLOSE  cur_emp_lock;
        --
        RAISE EX_INVALID_SALARY;
        --
      END IF;  
      --
    END IF;
    --
    -- 
    gc_error_point := 'PEMPUS9999';
    --
    EXCEPTION
      --    
      WHEN EX_INVALID_PERCENTAGE THEN
        --
        -- Invalid percentage passed in
        --
        pc_status := gc_fail;
        pn_err_no := cn_invalid_percentage;
        pc_err_msg := cc_invalid_percentage||pnm_percentage;
        pc_err_lvl := gc_error; 
        --      
      WHEN EX_INVALID_EMPLOYEE THEN
        --
        -- Invalid department id passed in
        --
        pc_status := gc_fail;
        pn_err_no := cn_invalid_employee;
        pc_err_msg := cc_invalid_employee;
        pc_err_lvl := gc_error; 
        --      
      WHEN EX_INVALID_SALARY THEN
        --
        -- Invalid department id passed in
        --
        pc_status := gc_fail;
        pn_err_no := cn_invalid_salary;
        pc_err_msg := cc_invalid_salary;
        pc_err_lvl := gc_error; 
        --      
      WHEN OTHERS THEN
       --
       IF ( SQLCODE = '-0054' ) 
       THEN
         --
         pc_status := gc_fail;
         pn_err_no := cn_record_locked;
         pc_err_msg := cc_record_locked;
         pc_err_lvl := gc_error;
         -- 
       ELSE
         --
         -- Fatal SQL errors
         --      
         pc_status := gc_fail;
         pn_err_no := SQLCODE;
         pc_err_msg := SQLERRM;
         pc_err_lvl := gc_fatal; 
         --
       END IF;
       --  
  END p_update_salary;    
  -- ---------------------------------------  
  PROCEDURE p_transfer_employee
  (  ptm_employee_id       IN EMPLOYEES.EMPLOYEE_ID%TYPE    
    ,ptm_new_department_id IN EMPLOYEES.DEPARTMENT_ID%TYPE
	,pc_status        OUT VARCHAR2
	,pn_err_no        OUT NUMBER
	,pc_err_msg       OUT VARCHAR2
	,pc_err_lvl       OUT VARCHAR2
  ) IS
    --
    -- Description: 
    -- Allow an employee to be transferred to a new department
    -- ptm_employee_id       => A valid employee_id
    -- ptm_new_department_id => The new valid department the employee is moving to
    --
    lt_department_id EMPLOYEES.DEPARTMENT_ID%TYPE;
    --
    CURSOR cur_emp_lock( it_emp_id EMPLOYEES.EMPLOYEE_ID%TYPE ) IS
      SELECT DEPARTMENT_ID
      FROM   EMPLOYEES e
      WHERE  e.EMPLOYEE_ID = it_emp_id
      FOR UPDATE OF e.DEPARTMENT_ID NOWAIT;
    --    
	EX_INVALID_EMPLOYEE EXCEPTION;
	EX_INVALID_DEPARTMENT   EXCEPTION;
	--
  BEGIN
    --
    -- Validate employee
    --
    gc_error_point := 'PEMMOV0000';
    --
    IF ( ptm_employee_id IS NULL
         OR 
         NOT f_is_valid_emp_id( ptm_emp_id => ptm_employee_id ) )    
    THEN
      --
      -- Not a valid employee
      --
      gc_error_point := 'PEMMOV0005';
      --
      RAISE EX_INVALID_EMPLOYEE;
      --      
    ELSIF ( ptm_new_department_id IS NOT NULL
            AND NOT f_is_valid_dept_id( ptm_dept_id => ptm_new_department_id ) ) THEN
      --
      gc_error_point := 'PEMMOV0010';
      --      
      RAISE EX_INVALID_DEPARTMENT;
      --
    END IF;
    --
    -- Valid employee and department so lock it
    --
    gc_error_point := 'PEMMOV0015';
    --
    OPEN cur_emp_lock( it_emp_id => ptm_employee_id );
    FETCH cur_emp_lock INTO lt_department_id;
    IF ( cur_emp_lock%FOUND 
         AND lt_department_id != ptm_new_department_id ) THEN
      --
      -- Only update if new department is different
      --
      gc_error_point := 'PEMMOV0020';
      --
      UPDATE EMPLOYEES
      SET DEPARTMENT_ID = ptm_new_department_id
      WHERE CURRENT OF cur_emp_lock;
      --
      pc_status := gc_pass;
      pn_err_no := cn_record_updated;
      pc_err_msg := cc_record_updated;
      pc_err_lvl := gc_info;
      --
    ELSE
      --
      -- Return warning user is already in the department
      --  
      --
      gc_error_point := 'PEMMOV0025';
      --
      pc_status := gc_pass;
      pn_err_no := cn_already_in_department;
      pc_err_msg := cc_already_in_department;
      pc_err_lvl := gc_warning; 
      --      
    END IF;
    --  
    CLOSE  cur_emp_lock;    
    --      
    gc_error_point := 'PEMMOV9999';
    --
  EXCEPTION
    --    
    WHEN EX_INVALID_EMPLOYEE THEN
      --
      -- Invalid department id passed in
      --
      pc_status := gc_fail;
      pn_err_no := cn_invalid_employee;
      pc_err_msg := cc_invalid_employee;
      pc_err_lvl := gc_error; 
      --      
    WHEN EX_INVALID_DEPARTMENT THEN
      --
      -- Invalid department id passed in
      --
      pc_status := gc_fail;
      pn_err_no := cn_invalid_department;
      pc_err_msg := cc_invalid_department;
      pc_err_lvl := gc_error; 
      --      
    WHEN OTHERS THEN
      --
      IF ( SQLCODE = '-0054' ) 
      THEN
        --
        pc_status := gc_fail;
        pn_err_no := cn_record_locked;
        pc_err_msg := cc_record_locked;
        pc_err_lvl := gc_error;
        -- 
      ELSE
        --
        -- Fatal SQL errors
        --      
        pc_status := gc_fail;
        pn_err_no := SQLCODE;
        pc_err_msg := SQLERRM;
        pc_err_lvl := gc_fatal; 
        --
      END IF;
      -- 
  END p_transfer_employee;    
  --	
  -- ---------------------------------------  
  FUNCTION f_get_emp_salary
  ( ptm_employee_id       IN EMPLOYEES.EMPLOYEE_ID%TYPE 
  ) RETURN NUMBER IS
  --
  -- f_get_emp_salary
  -- Description: 
  -- Returns employee yearly salary
  -- ptm_employee_id       ==> A valid employee_id
  --
  lt_salary EMPLOYEES.SALARY%TYPE;
  --
  CURSOR cur_emp( it_emp_id EMPLOYEES.EMPLOYEE_ID%TYPE ) IS
    SELECT SALARY
    FROM   EMPLOYEES
    WHERE  EMPLOYEE_ID = it_emp_id;
  --  
  BEGIN
    --
    OPEN cur_emp( it_emp_id => ptm_employee_id );
    FETCH cur_emp INTO lt_salary;
    CLOSE cur_emp;
    --
    RETURN( lt_salary );
    --
  END  f_get_emp_salary;
  -- -------------------------------------------------------
  PROCEDURE p_employee_report( pcm_report_type IN VARCHAR2
                              ,ptm_department_id IN EMPLOYEES.DEPARTMENT_ID%TYPE
                              ,pco_file_name IN VARCHAR2
                              ,pco_column_separator IN VARCHAR2 DEFAULT ','
                           	  ,pc_status        OUT VARCHAR2
	                          ,pn_err_no        OUT NUMBER
	                          ,pc_err_msg       OUT VARCHAR2
	                          ,pc_err_lvl       OUT VARCHAR2
	                         ) IS
  --	                         
  -- Description 	                         
  -- Produce employee reports in CSV formats
  -- pcm_report_type ==> The type of report. Valid Values 'ALL_EMP_DEPT_REPORT' for all employyees in a department
  --                                                      'EMP_SAL_DEPT_REPORT' total salary per department
  -- ptm_department_id  ==> The department Id can to report on 
  -- pco_file_name IN VARCHAR2 ==> The file name to be produced in extract folder 'EXTRACT_DIR' if none passed in defaulted to 
  -- report_type + YYMMDDHH24MISS.csv 
  -- pco_file_separator IN VARCHAR2  ==> Defaulted to comma if none passed in
  --
  lt_file  UTL_FILE.FILE_TYPE;
  lc_header VARCHAR2(2000);
  lc_column_separator VARCHAR2(20) := NVL( pco_column_separator, ',' ); 
  --  
  lc_file_name VARCHAR2(50);
  EX_INVALID_TYPE EXCEPTION;
  EX_INVALID_DEPARTMENT EXCEPTION;
  --
  -- The oracle directory where reports are written to
  --
  cc_oracle_directory VARCHAR2(20):= 'EXTRACT_DIR';
  --  
BEGIN
  --
  gc_error_point := 'PEMREP0000';
  --
  --
  -- Set column headers                         
  --                     
  IF ( pcm_report_type = 'ALL_EMP_DEPT_REPORT' )
  THEN
    --
    lc_header := 'EMPLOYEE_ID'||lc_column_separator
                 ||'EMPLOYEE_NAME'||lc_column_separator
                 ||'JOB_TITLE'||lc_column_separator
                 ||'MANAGER_ID'||lc_column_separator
                 ||'MANAGER_NAME'||lc_column_separator
                 ||'DATE_HIRED'||lc_column_separator     
                 ||'SALARY'||lc_column_separator
                 ||'DEPARTMENT_ID'||lc_column_separator
                 ||'DEPARTMENT_NAME'||lc_column_separator
                 ||'LOCATION';                 
    --             
  ELSIF ( pcm_report_type = 'EMP_SAL_DEPT_REPORT' )
  THEN
    --
    lc_header := 'DEPARTMENT_ID'||lc_column_separator
                 ||'DEPARTMENT_NAME'||lc_column_separator
                 ||'SALARY'||lc_column_separator;
  ELSE
    --
    -- Report type is not supported
    --
    RAISE EX_INVALID_TYPE;
    --
  END IF;
  --
  -- Validate department ID
  --
  IF ( ( ptm_department_id IS NOT NULL
         AND NOT f_is_valid_dept_id( ptm_dept_id => ptm_department_id ) 
        ) 
        OR 
        ( ptm_department_id IS NULL 
        )
      )
  THEN
    --
    gc_error_point := 'PEMREP0010';
    --      
    RAISE EX_INVALID_DEPARTMENT;
    --
  END IF;    
  --
  -- Default file name if none is passed in
  --
  lc_file_name := NVL( pco_file_name, pcm_report_type||'_'|| ptm_department_id||'_'||TO_CHAR( SYSDATE, 'YYMMDDHH24MISS' )||'.csv');
  --
  lt_file := UTL_FILE.FOPEN(location     => cc_oracle_directory,
                           filename     => lc_file_name,
                           open_mode    => 'w',
                           max_linesize => 32767);
  --                         
  gc_error_point := 'PEMREP0015';
  --   
  UTL_FILE.PUT_LINE(lt_file,
                    lc_header 
                    );
  --
  gc_error_point := 'PEMREP0020';  
  --         
  -- Retrieve report data
  --
  -- Note: For large data sets where performance could be an issue separate cursors and concatenation done 
  -- before writing to file
  --     
  -- SELECT statements in UNION are mutually exclusive
  --
  FOR cur_rec IN (  -- Select for employees in a given department
                    SELECT e.EMPLOYEE_ID||lc_column_separator
                           ||e.EMPLOYEE_NAME||lc_column_separator
                           ||e.JOB_TITLE||lc_column_separator
                           ||e.MANAGER_ID||lc_column_separator
                           ||e2.EMPLOYEE_NAME||lc_column_separator
                           ||TO_CHAR( e.DATE_HIRED, 'DD-Mon-YYYY' )||lc_column_separator     
                           ||e.SALARY||lc_column_separator
                           ||e.DEPARTMENT_ID||lc_column_separator
                           ||d.DEPARTMENT_NAME||lc_column_separator
                           ||d.LOCATION_ID out_rec
                   FROM  EMPLOYEES e
                        ,DEPARTMENTS d
                        ,EMPLOYEES e2                     
                   WHERE d.DEPARTMENT_ID = ptm_department_id
                   AND   e.DEPARTMENT_ID = d.DEPARTMENT_ID
                   AND   e2.EMPLOYEE_ID (+) = e.MANAGER_ID
                   AND   'ALL_EMP_DEPT_REPORT' = pcm_report_type    
                   UNION ALL
                   -- Select for total salary in a given department                   
                   SELECT e.DEPARTMENT_ID||lc_column_separator
                          ||d.DEPARTMENT_NAME||lc_column_separator
                          ||SUM( e.SALARY )
                     FROM  EMPLOYEES e
                          ,DEPARTMENTS d
                    WHERE  e.DEPARTMENT_ID = ptm_department_id
                    AND    e.DEPARTMENT_ID = d.DEPARTMENT_ID 
                    AND   'EMP_SAL_DEPT_REPORT' = pcm_report_type    
                    GROUP BY e.DEPARTMENT_ID,d.DEPARTMENT_NAME
                   ORDER BY 1
                 )
  LOOP
    --
    -- Write record to file
    --                         
    UTL_FILE.PUT_LINE(lt_file,
                      cur_rec.out_rec 
                      );
    --                  
  END LOOP;
  --
  gc_error_point := 'PEMREP0025';
  --
  -- Close the file
  --
  UTL_FILE.FCLOSE(lt_file);
  --
  gc_error_point := 'PEMREP0030';
  --
  pc_status := gc_pass;  
  pn_err_no := cn_report_created;
  pc_err_msg := cc_report_created||' '||lc_file_name;
  pc_err_lvl := gc_info; 
  --  
EXCEPTION
  --
  WHEN EX_INVALID_TYPE THEN
    --
    pc_status := gc_fail;
    pn_err_no := cn_invalid_rep_type;
    pc_err_msg := cc_invalid_rep_type;
    pc_err_lvl := gc_warning; 
    --
    WHEN EX_INVALID_DEPARTMENT THEN
      --
      -- Invalid department id passed in
      --
      pc_status := gc_fail;
      pn_err_no := cn_invalid_department;
      pc_err_msg := cc_invalid_department;
      pc_err_lvl := gc_error; 
      --      
  WHEN UTL_FILE.ACCESS_DENIED THEN
    --
    pc_status := gc_fail;
    pn_err_no  := cn_file_operation_err;
    pc_err_msg := cc_file_operation_err||'ACCESS_DENIED';
    pc_err_lvl := gc_fatal;
    -- 
  WHEN UTL_FILE.INVALID_FILENAME THEN
    --
    pc_status := gc_fail;
    pn_err_no  := cn_file_operation_err;
    pc_err_msg := cc_file_operation_err||'INVALID_FILENAME';
    pc_err_lvl := gc_fatal;
    -- 
  WHEN UTL_FILE.INVALID_PATH THEN
    --
    pc_status := gc_fail;
    pn_err_no  := cn_file_operation_err;
    pc_err_msg := cc_file_operation_err||'INVALID_PATH';
    pc_err_lvl := gc_fatal;
    -- 
  WHEN UTL_FILE.INVALID_MODE THEN
    --
    pc_status := gc_fail;
    pn_err_no  := cn_file_operation_err;
    pc_err_msg := cc_file_operation_err||'INVALID_MODE';
    pc_err_lvl := gc_fatal;
    -- 
  WHEN UTL_FILE.INVALID_OPERATION THEN
    --
    pc_status := gc_fail;
    pn_err_no  := cn_file_operation_err;
    pc_err_msg := cc_file_operation_err||'INVALID_OPERATION';
    pc_err_lvl := gc_fatal;
    -- 
  WHEN UTL_FILE.INVALID_MAXLINESIZE THEN
    --
    pc_status := gc_fail;
    pn_err_no  := cn_file_operation_err;
    pc_err_msg := cc_file_operation_err||'INVALID_MAXLINESIZE';
    pc_err_lvl := gc_fatal;
    -- 
  WHEN OTHERS THEN
    --    
    -- Fatal errors
    --     
    pc_status := gc_fail;
    pn_err_no := SQLCODE;
    pc_err_msg := SQLERRM;
    pc_err_lvl := gc_fatal; 
    --
END p_employee_report;
--    
END pkg_employee_maintenance;
/
