--#find invalid objects
SELECT
    owner,
    object_type,
    object_name
FROM
    all_objects
WHERE
    status = 'INVALID'
    AND owner IN (
        'DWH', 'OWS'
    )
ORDER BY
    object_type ASC,
    object_name ASC;
/
--#compile invalid objects

BEGIN
    FOR invalid_objects IN (
        SELECT
            owner,
            object_type,
            object_name
        FROM
            all_objects
        WHERE
            status = 'INVALID'
            AND owner = 'OWS'
    ) LOOP
        IF invalid_objects.object_type = 'PACKAGE' THEN
            dbms_ddl.alter_compile('PACKAGE',invalid_objects.owner,invalid_objects.object_name);
        ELSIF invalid_objects.object_type = 'PACKAGE BODY' THEN
            dbms_ddl.alter_compile('PACKAGE BODY',invalid_objects.owner,invalid_objects.object_name);
        ELSIF invalid_objects.object_type = 'PROCEDURE' THEN
            dbms_ddl.alter_compile('PROCEDURE',invalid_objects.owner,invalid_objects.object_name);
        ELSIF invalid_objects.object_type = 'FUNCTION' THEN
            dbms_ddl.alter_compile('FUNCTION',invalid_objects.owner,invalid_objects.object_name);
        ELSIF invalid_objects.object_type = 'TRIGGER' THEN
            dbms_ddl.alter_compile('TRIGGER',invalid_objects.owner,invalid_objects.object_name);
        END IF;
    END LOOP;

    FOR cur IN (
        SELECT
            object_name,
            object_type,
            owner
        FROM
            sys.all_objects
        WHERE
            object_type = 'VIEW'
            AND owner = 'OWS'
            AND status = 'INVALID'
    ) LOOP
        BEGIN
            IF cur.object_type = 'PACKAGE BODY' THEN
                EXECUTE IMMEDIATE 'alter '
                                  || cur.object_type
                                  || ' "'
                                  || cur.owner
                                  || '"."'
                                  || cur.object_name
                                  || '" compile body';

            ELSE
                EXECUTE IMMEDIATE 'alter '
                                  || cur.object_type
                                  || ' "'
                                  || cur.owner
                                  || '"."'
                                  || cur.object_name
                                  || '" compile';
            END IF;

        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
    END LOOP;

END;
/

--#PRE ETL

DECLARE
    message   dtype.longstr%TYPE;
    errm      dtype.longstr%TYPE;
BEGIN
    dbms_output.disable ();
  
  -- turn off dynamic sampling on session level for ETL related activities
    EXECUTE IMMEDIATE 'alter session set optimizer_dynamic_sampling = 0';
    soft.start_simple(computername => sys_context('USERENV','HOST',255),clientapp => 'Pre ETL',appversion => NULL);

    message := opt_etl.inc_pre_etl_load_all_fi;
    IF substr(message,1,1) = stnd.error THEN
        raise_application_error(-20002,message);
    END IF;

    soft.finish_simple ();
EXCEPTION
    WHEN OTHERS THEN
        errm := sqlerrm;
        dbms_output.put_line(errm);
        raise_application_error(-20020,'Fatal error in Pre-ETL Incr for all FI: '
                                        || errm
                                        || chr(10)
                                        || dbms_utility.format_error_backtrace() );

END;
/
--#find not ready object
SELECT
    NULL fi_code,
    'APPL_INFO_TYPE' object_type,
    id   object_id,
    name
FROM
    appl_info_type
WHERE
    amnd_state = 'A'
    AND is_ready = 'N'
UNION ALL
SELECT
    NULL fi_code,
    'APPL_TYPE' object_type,
    id   object_id,
    name
FROM
    appl_type
WHERE
    amnd_state = 'A'
    AND is_ready = 'N'
    AND name NOT IN (
        'Account Transfer',
        'Update Contract'
    )
UNION ALL
SELECT
    NULL fi_code,
    'DATE_SCHEME' object_type,
    id   object_id,
    name
FROM
    date_scheme
WHERE
    amnd_state = 'A'
    AND is_ready = 'N'
UNION ALL
SELECT
    NULL fi_code,
    'TD_AUTH_TYPE' object_type,
    id   object_id,
    name
FROM
    td_auth_type
WHERE
    amnd_state = 'A'
    AND is_ready = 'N'
UNION ALL
SELECT
    NULL fi_code,
    'INST_SCHEME' object_type,
    id   object_id,
    name
FROM
    inst_scheme
WHERE
    amnd_state = 'A'
    AND inst_scheme__oid IS NULL
    AND is_ready = 'N'
UNION ALL
SELECT
    NULL fi_code,
    'INST_EVENT_FEE' object_type,
    id   object_id,
    ywinst_event_fee('INST_SCHEME__OID',inst_scheme__oid,NULL)
    || '-'
    || ywinst_event_fee('FEE_TYPE',fee_type,NULL) name
FROM
    inst_event_fee
WHERE
    amnd_state = 'A'
    AND is_ready = 'N'
UNION ALL
SELECT
    NULL fi_code,
    'INVOICE_EVENT' object_type,
    id             object_id,
    invoice_code   name
FROM
    invoice_event
WHERE
    amnd_state = 'A'
    AND is_ready = 'N'
UNION ALL
SELECT
    NULL fi_code,
    'SCH_JOB' object_type,
    id   object_id,
    name
FROM
    sch_job
WHERE
    amnd_state = 'A'
    AND is_ready = 'N'
    AND master_job IS NULL
    AND instr(comments,'NI_IN_USE=N') > 0
UNION ALL
SELECT
    NULL fi_code,
    'TARIFF' object_type,
    id   object_id,
    '('
    || ywtariff('TARIFF_DOMAIN__OID',tariff_domain__oid,NULL)
    || '):'
    || name name
FROM
    tariff
WHERE
    amnd_state = 'A'
    AND tariff_domain__oid NOT IN (
        SELECT
            id
        FROM
            tariff_domain
        WHERE
            amnd_state = 'A'
            AND is_personal = 'Y'
    )
    AND is_ready = 'N'
UNION ALL
SELECT
    (
        SELECT
            name
        FROM
            pm_bank
        WHERE
            id = pm_bank__oid
    ) fi_code,
    'PM_PARMS' object_type,
    id   object_id,
    name
FROM
    pm_parms
WHERE
    amnd_state = 'A'
    AND is_ready = 'N'
UNION ALL
SELECT
    opt_util.branch_code(f_i) fi_code,
    'ACC_SCHEME' object_type,
    id            object_id,
    scheme_name   name
FROM
    acc_scheme acs
WHERE
    amnd_state = 'A'
    AND is_ready = 'N'
UNION ALL
SELECT
    opt_util.branch_code(f_i) fi_code,
    'ACC_TEMPL' object_type,
    id             object_id,
    account_name   name
FROM
    acc_templ act
WHERE
    amnd_state = 'A'
    AND is_ready = 'N'
    AND acc_scheme__oid IS NOT NULL
UNION ALL
SELECT
    opt_util.branch_code(f_i) fi_code,
    'ACNT_CONTRACT' object_type,
    id                object_id,
    contract_number   name
FROM
    acnt_contract
WHERE
    amnd_state = 'A'
    AND pcat = 'B'
    AND is_ready = 'N'
UNION ALL
SELECT
    opt_util.branch_code(f_i) fi_code,
    'SERV_PACK' object_type,
    id   object_id,
    name
FROM
    serv_pack
WHERE
    amnd_state = 'A'
    AND is_ready = 'N'
UNION ALL
SELECT
    opt_util.branch_code(f_i) fi_code,
    'SERVICE' object_type,
    id   object_id,
    name
FROM
    service
WHERE
    amnd_state = 'A'
    AND is_ready = 'N'
    AND serv_pack__oid IS NOT NULL
UNION ALL
SELECT
    opt_util.branch_code(f_i) fi_code,
    'APPL_PRODUCT' object_type,
    id   object_id,
    name
FROM
    appl_product
WHERE
    amnd_state = 'A'
    AND is_ready = 'N'
/

--#complete timestamp

ALTER SESSION SET nls_date_format = 'dd/mm/yyyy hh24:mi:ss';
/
--#unilanguage

SELECT
    unistr('')
FROM
    dual;

SELECT
    asciistr('')
FROM
    dual;
/
--#git cherry pick

git cherry-pick <commit-hash>
git cherry-pick -x <commit-hash>
git notes copy <from> <to>
git revert <commit-hash>
/
--#get connection id 
declare
fsession        dtype.tag           %type := stnd.no; BEGIN
    IF ( stnd.connectionid IS NULL ) THEN
        soft.start_simple(sys_context('USERENV','HOST',255),sys_context('USERENV','MODULE',255),NULL);
        fsession := stnd.yes;
    END IF;
    dbms_output.put_line(stnd.connectionid);
end;
/
--#collect opt_tr_dump
opt_tr_dump.TR_DUMP_COLLECTION(164620980);
/
--#region PI
ROOT\OpenWay\Full\Configuration Setup\Main Tables\System Instances - Simple
/
--transaction code
SELECT
     val.code,
     val.name,
     mot.code,
     val.add_info   val_ad3,
     rec.add_info   rec_add,
     rec.id         recid,
     val.id         valid
 FROM
     sy_conf_group_val val,
     sy_conf_group_rec rec,
     mp_operation_type mot
 WHERE
     val.sy_conf_group__oid IN (
         SELECT
             id
         FROM
             sy_conf_group
         WHERE
             amnd_state = 'A'
             AND group_code = '017_TXN_CODE'
     )
--  and val.code='020'
     AND val.code in ( '851','731')
     AND val.id = rec.value_id
     AND rec.table_rec_id = mot.id
     AND rec.amnd_state = 'A'
     AND val.amnd_state = 'A';
/
--#oper type
ROOT\ENBD\Transaction Mapping\ENBD.Sy Conf Group Group
/
--#extract OPT_Z
select * from OPT_CTR_EX_ITEMS;
select  sel.*
  from TABLE(opt_ctr_add.GET_EX(
      ExGroup       => '0-FI'   -- Choose the ExGroup where your table is located
   , TableCodes    => 'APPL_PRODUCT'  -- Filter the list of tables you want to extract (comma separated)
   , FiCode        => '141' -- FI Code for the base FI Filter
   , FileNameTempl => '{PREFIX}-{MTAB_CODE}-{SUFFIX}.sql' -- This represents the grouping of extracts into files. Only used for full target state extract
   , AddFilter     => q'[code = '141_CHAIN_L3']' -- Your filter (note, filter must be between the [] as shown there
   , SingleMain    => 'N'
   , ExcludeTables => ''
   , DefSubFolder => ''
  )) sel;
/
--#get card range
SELECT
    main_products.name   account_product,
    sub_products.name    card_product,
    cs.prefix            bin,
    cs.min_number        min_range,
    cs.max_number        max_range,
    glob.get_tag_value(cs.add_parms,'REPL_MIN') repl_min_range,
    glob.get_tag_value(cs.add_parms,'REPL_MAX') repl_max_range
FROM
    appl_product main_products
    JOIN appl_product sub_products ON main_products.id = sub_products.appl_product__oid
                                      AND sub_products.amnd_state = 'A'
                                      AND sub_products.con_cat = 'C'
                                      and sub_products.contract_role = 'MAIN_CARD'
    JOIN contr_subtype cs ON sub_products.contr_subtype = cs.id
WHERE
    main_products.amnd_state = 'A'
    AND main_products.ccat = 'P'
    AND main_products.con_cat = 'A'
    AND main_products.liab_category IS NULL
    AND main_products.f_i IN (
--        opt_util.get_fi_id('010'),
--        opt_util.get_fi_id('011'),
--        opt_util.get_fi_id('012'),
--        opt_util.get_fi_id('033'),
--        opt_util.get_fi_id('101'),
        opt_util.get_fi_id('017')
--        ,
--        opt_util.get_fi_id('034')
    )
ORDER BY
    main_products.code ASC;
/
--#reference number
ROOT\EGCC\Configuration Tools\EGCC.Reference Numbers Handbook
/
--#process waiting object tasks
DECLARE
  FileName CONSTANT dtype.Name%type := 'Temporary-Process Waiting Tasks.sql'; -- This is used to align runbook with Process Name in Way4
  ToStartSession dtype.Tag%type := stnd.Yes;
  CommitInterval dtype.Counter%type := null; --Please only use for really big changes because, when used, the rollback in case of a process reject will not be full.
  OfficerUserId dtype.Name%type := 'OWS_A';
  
  ErrMsg dtype.ErrorMessage%type; --this can be used when calling functions that return dtype.ErrorMessage%type
  ToReject dtype.Tag%type; AppErrorText dtype.LongStr%type; AppErrorNumber dtype.Counter%type; --here we can put values to get the process rolled back and rejected
  
  
  -- Define your variables here
    n             dtype. RecordID         %type;
BEGIN
 /*NEVER DELETE THIS*/ opt_ctr_util.RELEASE_SUBPROCESS_START_P(ProcessName => FileName, ToStartSession => ToStartSession, OfficerUserId => OfficerUserId); --other parms are ProcessParms, IsUnique, ObjectType, ObjectId
    
  -- do your stuff
  for waitingTasks in (select * from sy_object_task where status = 'W')
  loop
    ErrMsg := objtsk.TASK_PROCESS_WAITING(waitingTasks.id);
    n := sy_process.add_current_number(1);   
  end loop;
  
  
  /*NEVER DELETE THIS*/ opt_ctr_util.RELEASE_SUBPROCESS_END2(ToReject, AppErrorText, AppErrorNumber); --Closes the current process and session if needed, will reject if ToReject was set to stnd.Yes.
end;
/
--#auth drop global parms
PI_CLEAR_OLD_PENDINGS=Y;
--product parms AUTH_DAYS 
/
--#target state specific tariff
POST_CC|025_EIB-5886_TARIFF-017_MAIN-ZERO_JOINING_FEE.sql
/
--#find new line LF in notepad++
find what: ^(.*?|^\r)\n
search mode: â€œregular expressionâ€?
/
--#loyalty rules
ROOT\All USERS\Production Support\ENBD\EGCC Loyalty\EGCC.Loyalty Parameters
/
--#loyalty bonus PRD-16004
WITH set0 AS (
    SELECT /*+MATERIALIZED*/
        a.id                account_id,
        c.id                card_id,
        a.contract_number   account,
        c.contract_number   card,
        substr(d.code, 9, 3) AS logo,
        substr(d.code, 13, 3) AS pct,
        tas.auth_idt        skywards_number,
        (
            SELECT
                MIN(t.name
                    || ': '
                    || TO_CHAR(e.posting_date, 'YYYY-MM-DD')
                    || ', '
                    || e.fee_amount)
            FROM
                account a
                JOIN item i ON a.id = i.account__oid
                JOIN entry e ON i.id = e.item__id
                JOIN doc d ON d.id = e.doc_id
                JOIN trans_type t ON t.id = d.trans_type
            WHERE
                a.acnt_contract__oid = c.acnt_contract__oid
                AND i.number_of_docs > 0
                AND t.trans_type_idt IN (
                    'LTY_BON_USG'
                )
                AND ( e.is_reversed IS NULL
                      OR e.is_reversed NOT IN (
                    'Z',
                    '~'
                ) )
        ) AS bonus_miles
    FROM
        acnt_contract c
        JOIN acnt_contract a ON c.acnt_contract__oid = a.id
        JOIN add_pack_inc t ON c.id = t.acnt_contract__oid
        JOIN tariff_domain d ON t.add_pack = d.id
        JOIN f_i fi ON fi.id = c.f_i
                       AND fi.amnd_state = 'A'
                       AND fi.bank_code = '017'
        JOIN td_auth_sch tas ON tas.acnt_contract__id = c.id
                                AND tas.amnd_state = 'A'
        JOIN td_auth_type tat ON tas.auth_type = tat.id
                                 AND tat.amnd_state = 'A'
                                 AND tat.code = 'SKYWARDS'
    WHERE
        c.con_cat = 'C'
        AND t.pack_type IN (
            'EVENT_DOMAIN',
            'OWN_DOMAIN'
        )
        AND t.is_active = 'Y'
        AND d.code IN (
            '017_AED_016_620',
            '017_AED_016_920',
            '017_AED_016_921'
        )
)
SELECT
    *
FROM
    set0;
/
--#DM regression opt_dm_transaction
WITH exists_08b AS (
    SELECT
        contract_idt,
        txn_code,
        amount
    FROM
        opt_dm_transaction
    WHERE
        org = '100'
        AND banking_date = TO_DATE('02-03-2021', 'DD-MM-YYYY')
    MINUS
    SELECT
        contract_idt,
        txn_code,
        amount
    FROM
        opt_dm_transaction@dmprf08r
    WHERE
        org = '100'
        AND banking_date = TO_DATE('02-03-2021', 'DD-MM-YYYY')
), exists_08r AS (
    SELECT
        contract_idt,
        txn_code,
        amount
    FROM
        opt_dm_transaction@dmprf08r
    WHERE
        org = '100'
        AND banking_date = TO_DATE('02-03-2021', 'DD-MM-YYYY')
    MINUS
    SELECT
        contract_idt,
        txn_code,
        amount
    FROM
        opt_dm_transaction
    WHERE
        org = '100'
        AND banking_date = TO_DATE('02-03-2021', 'DD-MM-YYYY')
)
SELECT
    'EXISTS_08B' status,
    logo,
    exists_08b.txn_code,
    SUM(exists_08b.amount) diff08b,
    NULL diff08r
FROM
    exists_08b
    JOIN opt_dm_contract_info ci ON exists_08b.contract_idt = ci.contract_idt
GROUP BY
    logo,
    txn_code
UNION ALL
SELECT
    'EXISTS_08R' status,
    logo,
    exists_08r.txn_code,
    NULL diff08b,
    SUM(exists_08r.amount) diff08r
FROM
    exists_08r
    JOIN opt_dm_contract_info ci ON exists_08r.contract_idt = ci.contract_idt
GROUP BY
    logo,
    txn_code
ORDER BY
    logo,
    txn_code,
    status;
/
--#opt_dm_txn details
SELECT
    contract_idt,
    txn_code,
    amount
FROM
    opt_dm_transaction
WHERE
    org = '100'
    AND banking_date = TO_DATE('02-03-2021', 'DD-MM-YYYY')
MINUS
SELECT
    contract_idt,
    txn_code,
    amount
FROM
    opt_dm_transaction@dmprf08b
WHERE
    org = '100'
    AND banking_date = TO_DATE('02-03-2021', 'DD-MM-YYYY')
ORDER BY
    contract_idt, txn_code;
/
--#add superuser role

 begin
    opt_z_officer_used_role.ron(dialect => NULL,p_r_officer_group__oid => 'SUPERUSER',p_r_officer_role__id => 'CSS_ALL');

    COMMIT;

end;
/
--#block code contract status mapping

SELECT    sh.filter2,
    sh.filter3   card_block,
    sh.filter4,
    cs.external_code,
    DECODE(external_code,'BCA_00_N','3','BCA_05_N','3','BCA_05_IA','3','BCA_04_N','3','BCA_04_ID','3','BCC_00_N','1','BCC_05_N','4'
   ,'BCC_05_IA','4','BCC_04_N','2','BCC_04_IA','2','BCC_04_N_L','2','BCC_04_N_S','2','BCC_05_N_4','6','UNKNOWN') b24_card_stat,
    cs.code      response_code,
    cs.is_valid
FROM
    sy_handbook sh
    JOIN contr_status cs ON cs.external_code = sh.code
                            AND cs.amnd_state = 'A'
WHERE
    sh.amnd_state = 'A'
    AND sh.group_code = 'BLOCK_CODE_ACNT_STATUS'
    AND sh.filter = '017'
--            AND sh.filter2 = 'C'
ORDER BY
    filter2 ASC,
    filter3 ASC;
/
--#update billing date
DECLARE
    rc   dtype.counter%TYPE;

    PROCEDURE setbillingdate (
        contractnumber   dtype.name%TYPE,
        billingday       dtype.name%TYPE
    ) IS

        acid                 dtype.recordid%TYPE;
        n_cycle              dtype.recordid%TYPE;
        acnt                 acnt_contract%rowtype;
        duedate              dtype.name%TYPE;
        cstype               dtype.recordid%TYPE;
        csvalue              dtype.recordid%TYPE;
        informationmessage   dtype.errormessage%TYPE;
        errmsg               dtype.errormessage%TYPE;
    BEGIN
        stnd.process_message('I','Updating account ' || contractnumber);
        SELECT
            MIN(id)
        INTO acid
        FROM
            acnt_contract
        WHERE
            amnd_state = 'A'
            AND contract_number = contractnumber;

        SELECT
            nvl(MAX(n_of_cycle),0)
        INTO n_cycle
        FROM
            account
        WHERE
            acnt_contract__oid = acid;

        IF n_cycle != 0 THEN
            stnd.process_message(stnd.error,'Can not update billing date for account '
                                              || contractnumber
                                              || ': not the first cycle');
            return;
        END IF;

        ygacnt_contract(acid,acnt);
        duedate := glob.get_tag_value(acnt.ext_data,'DUE_DATE');
        acnt.ext_data := sy_convert.remove_tag(acnt.ext_data,'DUE_DATE');
        ytacnt_contract('P',NULL,acnt);
        decr.get_status_value(NULL,NULL,NULL,'BILLING_DAY',to_number(substr(billingday,1,2) ),cstype,csvalue,informationmessage);

        IF informationmessage IS NOT NULL THEN
            stnd.process_message(substr(informationmessage,1,1),substr(informationmessage,3) );
        END IF;

        IF cstype IS NOT NULL AND csvalue IS NOT NULL THEN
            decr.set_status(acnt.id,NULL,NULL,cstype,csvalue,NULL,NULL,NULL,NULL,'Billing Date update script',errmsg);

            IF errmsg IS NOT NULL THEN
                stnd.process_message('I',errmsg);
            END IF;
        --eoc.SET_NEXT_BILLING(Acnt.id, to_date(BillingDay, 'DDMMYYYY'));
        --update acnt_contract set next_billing_date=to_date(BillingDay, 'DDMMYYYY') where id = Acnt.id;
            acnt.next_billing_date := TO_DATE(billingday,'DDMMYYYY');
        END IF;

        acnt.ext_data := glob.set_tag_value(acnt.ext_data,'DUE_DATE',duedate);
        ytacnt_contract('P',NULL,acnt);
    END;

BEGIN
  -- Start session if required
    IF stnd.connectionid IS NULL THEN
        soft.start_simple(sys_context('USERENV','HOST',255),sys_context('USERENV','MODULE',255) /* or session name */,NULL);
    END IF;   
  -- Start process

    rc := ows.sy_process.process_start('Update billing date',NULL,ows.stnd.yes);

    setbillingdate('0005228730066500916','06062021');
    COMMIT;
    sy_process.process_end ();
    soft.finish_simple;
END;
/
--# Reproduce PRN report
BEGIN
    FOR card IN (
        SELECT
            ci.*
        FROM
            ows.acnt_contract ac
            JOIN ows.card_info ci ON ci.acnt_contract__oid = ac.id
                                     AND ci.prod_date IS NOT NULL
                                     AND ci.date_from = '02-MAR-21'
        WHERE
            ac.amnd_state = 'A'
            AND ( ac.f_i = ows.opt_util.get_fi_id('034')
                  OR ac.f_i = ows.opt_util.get_fi_id('017')
                  OR ac.f_i = ows.opt_util.get_fi_id('016') )
    ) LOOP
        UPDATE ows.acnt_contract
        SET
            production_status = 'M'
        WHERE
            id = card.acnt_contract__oid;        
        UPDATE ows.card_info
        SET
            pin = NULL,
            status = 'I'
        WHERE
            id = card.id;        
        COMMIT;
    END LOOP;
END;
/
update ows.pm_job set production_status = 3;
update ows.pm_task set production_status = 3;
commit;
/
--#GL
SELECT
    gtrans.ref_number,
    gtrace.amount,
    gtrace.cr_account,
    credit_contract.contract_number,
    gtrace.cr_account_number,
    gtrans.cr_number,
    gtrace.dr_account,
    debit_contract.contract_number,
    gtrace.dr_account_number,
    gtrans.dr_number
FROM
    ows.gl_transfer gtrans,
    ows.gl_trace gtrace,
    ows.m_transaction mtrans,
    ows.doc doc,
    ows.account credit_account,
    ows.account debit_account,
    ows.acnt_contract credit_contract,
    ows.acnt_contract debit_contract
WHERE
    gtrans.ref_number = '99385304619520162686897581531705'
    AND gtrace.gl_transfer__id = gtrans.id
    AND gtrace.m_transaction__id = mtrans.id
    AND mtrans.doc__oid = doc.id
    AND credit_account.id = gtrace.cr_account
    AND debit_account.id = gtrace.dr_account
    AND credit_account.acnt_contract__oid = credit_contract.id
    AND debit_account.acnt_contract__oid = debit_contract.id;
/
--GL Auto Format
LE       := opt_calc.GET_PARMPLUS (ContractRec, NULL, 'LE'); --legal entity
PC       := opt_calc.GET_PARMPLUS (ContractRec, NULL, 'PC'); --product code
RC       := api.GET_CS_VALUE (ContractRec.id, NULL, 'GL_RC'); --response center
CIF      := ClientRec.REG_NUMBER; --client reg number
GL_NUM := NVL (LE, '1355') || NVL (RC, '0000') || NVL (PC, '0000') || NVL (AccTempl.gl_number,'000000') || NVL (CIF, '');
AnalyticRefN = gl_trace.id
SynthRefN = gl_transfer.ref_number
GroupRefN = gl_transfer.ref_number_<m_transaction.id>
/
--#PCMS
table prefix TBLGUI
/
--GL details based on doc or mtrans
SELECT
    CASE
        WHEN substr(opt_forms.get_txn_code(gl_trace.dr_main_entry),-3) = 'N/A' THEN substr(opt_forms.get_txn_code(gl_trace.cr_main_entry
        ),-3)
        ELSE substr(opt_forms.get_txn_code(gl_trace.dr_main_entry),-3)
    END txn_code,
    gl_transfer.order_date,
    gl_transfer.ref_number,
    gl_transfer.gl_trans_code,
    m_transaction.doc__oid            doc_id,
    m_transaction.id                  m_transaction_id,
    m_transaction.service_class,
    gl_trace.id                       gl_trace_id,
    contract_debit.contract_number    contract_debit,
    account_debit.code                debit_account_code,
    account_debit.account_name        debit_account_name,
    gl_trace.dr_account,
    gl_trace.dr_account_number,
    gl_transfer.dr_number,
    contract_credit.contract_number   contract_credit,
    account_credit.code               credit_account_code,
    account_credit.account_name       credit_account_name,
    gl_trace.cr_account,
    gl_trace.cr_account_number,
    gl_transfer.cr_number
FROM
    m_transaction,
    gl_trace,
    gl_transfer,
    account account_credit,
    account account_debit,
    acnt_contract contract_credit,
    acnt_contract contract_debit
WHERE
    m_transaction.doc__oid = <doc_id>
    --m_transaction.id = <m_transaction_id>
    AND m_transaction.id = gl_trace.m_transaction__id
    AND gl_trace.gl_transfer__id = gl_transfer.id
    AND account_credit.id = gl_trace.cr_account
    AND account_debit.id = gl_trace.dr_account
    AND account_credit.acnt_contract__oid = contract_credit.id
    AND account_debit.acnt_contract__oid = contract_debit.id
    --AND m_transaction.service_class IN (
        --'T',
        --'M'
    --)
    ;
/
select sel.*
from TABLE(opt_ctr_add.GET_EX(
ExGroup => '0-HB'
, TableCodes => 'SY_HANDBOOK'
, FiCode => ''
, FileNameTempl => 'GLOBAL-TGT-{PREFIX}-{MTAB_CODE}-{SUFFIX}.sql'
, AddFilter => q'[GROUP_CODE in('ACCOUNT_BOARDING') and CODE in('017')]'
, SingleMain => 'N'
, ExcludeTables => ''
, DefSubFolder => ''
)) sel
/
--#amount_formula
select opt_calc.FORMULA_AMOUNT(281779082, (select apply_rules from tariff where id = 90430822)) amount from dual;
/
WITH txn_code AS (
    SELECT
        '660' code
    FROM
        dual
)
SELECT
    'PRIVATE',
    s.service_class,
    scgv.code,
    scgv.name,
    mot.code,
    mot.name,
    ts.name,
    sp.name,
    s.name,
    s.account_type,
    s.fee_account,
    at.name,
    at.code,
    na.code,
    na.filter5,
    na.name,
    na.filter3,
    NULL
FROM
    txn_code tc,
    sy_conf_group_group scgg,
    sy_conf_group scg,
    sy_conf_group_val scgv,
    sy_conf_group_rec scgr,
    mp_operation_type mot,
    mp_operation_type_rule motr,
    f_i fi,
    trans_type tt,
    trans_subtype ts,
    service s,
    serv_pack sp,
    account_type at,
    (
        SELECT
            *
        FROM
            sy_handbook
        WHERE
            amnd_state = 'A'
            AND group_code = 'GL_AUTO'
    ) na
WHERE
    scgg.amnd_state = 'A'
    AND scgg.code = '017_TXN_CODE'
    AND scgg.id = scg.sy_conf_group_group__oid
    AND scgv.sy_conf_group__oid = scg.id
    AND scgv.amnd_state = 'A'
    AND scgr.value_id = scgv.id
    AND mot.id = scgr.table_rec_id
    AND motr.amnd_state = 'A'
    AND motr.mp_operation_type__oid = mot.id
    AND motr.f_i = fi.id
    AND fi.amnd_state = 'A'
    AND fi.bank_code = '017'
    AND motr.trans_type = tt.id
    AND tt.id = ts.trans_type__oid
    AND tt.amnd_state = 'A'
    AND ts.amnd_state = 'A'
    AND s.trans_type_t = ts.id
    AND s.f_i = fi.id
    AND sp.id = s.serv_pack__oid
    AND s.amnd_state = 'A'
    AND sp.amnd_state = 'A'
    AND at.id = s.account_type
    AND at.code = na.filter4
    AND na.filter2 = fi.bank_code
    AND scgv.code = tc.code
UNION ALL
SELECT
    'BANK',
    s.service_class,
    scgv.code,
    scgv.name,
    mot.code,
    mot.name,
    ts.name,
    sp.name,
    s.name,
    s.account_type,
    s.fee_account,
    NULL,
    NULL,
    atmpl.gl_number,
    atmpl.hd_gl_number,
    atmpl.gl_number,
    atmpl.gl_number,
    asch.scheme_name
FROM
    txn_code tc,
    sy_conf_group_group scgg,
    sy_conf_group scg,
    sy_conf_group_val scgv,
    sy_conf_group_rec scgr,
    mp_operation_type mot,
    mp_operation_type_rule motr,
    f_i fi,
    trans_type tt,
    trans_subtype ts,
    service s,
    serv_pack sp,
    account_type at,
    acc_templ atmpl,
    acc_scheme asch
WHERE
    scgg.amnd_state = 'A'
    AND scgg.code = '017_TXN_CODE'
    AND scgg.id = scg.sy_conf_group_group__oid
    AND scgv.sy_conf_group__oid = scg.id
    AND scgv.amnd_state = 'A'
    AND scgr.value_id = scgv.id
    AND mot.id = scgr.table_rec_id
    AND motr.amnd_state = 'A'
    AND motr.mp_operation_type__oid = mot.id
    AND motr.f_i = fi.id
    AND fi.amnd_state = 'A'
    AND fi.bank_code = '017'
    AND motr.trans_type = tt.id
    AND tt.id = ts.trans_type__oid
    AND tt.amnd_state = 'A'
    AND ts.amnd_state = 'A'
    AND s.trans_type_s = ts.id
    AND s.f_i = fi.id
    AND sp.id = s.serv_pack__oid
    AND s.amnd_state = 'A'
    AND sp.amnd_state = 'A'
    AND at.id = s.account_type
    AND at.id = atmpl.account_type__id
    AND atmpl.f_i = fi.id
    AND atmpl.amnd_state = 'A'
    AND atmpl.acc_scheme__oid = asch.id
    AND scgv.code = tc.code
UNION ALL
SELECT
     'BANK',
     s.service_class,
     scgv.code,
     scgv.name,
     mot.code,
     mot.name,
     ts.name,
     sp.name,
     s.name,
     s.account_type,
     s.fee_account,
     at.name,
     at.code,
     atmpl.gl_number,
     atmpl.hd_gl_number,
     atmpl.gl_number,
     atmpl.gl_number,
     asch.scheme_name
 FROM
     txn_code tc,
     sy_conf_group_group scgg,
     sy_conf_group scg,
     sy_conf_group_val scgv,
     sy_conf_group_rec scgr,
     mp_operation_type mot,
     mp_operation_type_rule motr,
     f_i fi,
     trans_type tt,
     trans_subtype ts,
     service s,
     serv_pack sp,
     account_type at,
     account a,
     acc_templ atmpl,
     acc_scheme asch
 WHERE
     scgg.amnd_state = 'A'
     AND scgg.code = '017_TXN_CODE'
     AND scgg.id = scg.sy_conf_group_group__oid
     AND scgv.sy_conf_group__oid = scg.id
     AND scgv.amnd_state = 'A'
     AND scgr.value_id = scgv.id
     AND mot.id = scgr.table_rec_id
     AND motr.amnd_state = 'A'
     AND motr.mp_operation_type__oid = mot.id
     AND motr.f_i = fi.id
     AND fi.amnd_state = 'A'
     AND fi.bank_code = '017'
     AND motr.trans_type = tt.id
     AND tt.id = ts.trans_type__oid
     AND tt.amnd_state = 'A'
     AND ts.amnd_state = 'A'
     AND s.trans_type_t = ts.id
     AND s.f_i = fi.id
     AND sp.id = s.serv_pack__oid
     AND s.amnd_state = 'A'
     AND sp.amnd_state = 'A'
     AND a.id = s.fee_account
     AND a.acc_templ__id = atmpl.id
     AND atmpl.acc_scheme__oid = asch.id
     AND atmpl.f_i = fi.id
     AND at.id = atmpl.account_type__id
    AND scgv.code = tc.code
--ORDER BY
--    sp.name ASC,
--    at.code ASC
    ;
/