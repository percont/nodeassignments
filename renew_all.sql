DECLARE
  FileName CONSTANT dtype.Name%type := 'renew_all.sql';
  ToStartSession dtype.Tag%type := stnd.Yes;
  CommitInterval dtype.Counter%type := 5; --Please only use for really big changes because, when used, the rollback in case of a process reject will not be full. This helps processing the CommitInterval automatically: opt_ctr_util.INCREMENT_ON_COMMIT_INTERVAL1(CommitInterval);
  OfficerUserId dtype.Name%type := 'OWS_A';
  
  ErrMsg dtype.ErrorMessage%type; --this can be used when calling functions that return dtype.ErrorMessage%type
  ToReject dtype.Tag%type; AppErrorText dtype.LongStr%type; AppErrorNumber dtype.Counter%type; --here we can put values to get the process rolled back and rejected
BEGIN
  /*NEVER DELETE THIS*/ opt_ctr_util.RELEASE_SUBPROCESS_START_P(ProcessName => FileName, ToStartSession => ToStartSession, OfficerUserId => OfficerUserId); --other parms are ProcessParms, IsUnique, ObjectType, ObjectId
  
  opt_flex_tools.APPROVE_ALL_GLOBAL      (                    DateFromLiteral => '', ForceDateFrom => null, CommitInterval => CommitInterval                    );
  opt_flex_tools.APPROVE_ALL_FI_BY_FILTER(FiFilter => 'ALL',  DateFromLiteral => '', ForceDateFrom => null, CommitInterval => CommitInterval, SkipParms => null );
  
  --<<********************************************Start tariff-related objects*******************************************
  sy_process.PROCESS_MESSAGE(stnd.Information, 'renew_all.sql: Action STARTED: Approve TARIFFS');
  update v_local_constants
    set date_from = glob.LDATE + 1, date_to = null;
  
  for rec in (
    select  t_id, tariff_domain__oid, t_name, t_is_ready
          , tv_id, tv_is_ready, tv_date_from
          , rnum
      from (
        select  t.id t_id, t.tariff_domain__oid, t.name t_name, t.is_ready t_is_ready
              , tv.id tv_id, tv.is_ready tv_is_ready, tv.date_from tv_date_from
              , row_number() over (partition by t.id order by tv.id desc) t_rnum
              , rownum rnum
          from tariff t
            join tariff_domain td
              on td.id = t.tariff_domain__oid
            left join tariff_data tv
              on tv.tariff__oid = t.id and tv.amnd_state = 'A'
          where t.amnd_state = 'A'
            and td.is_personal = 'N'
        )
      where t_rnum = 1
        and (t_is_ready != 'Y' or tv_is_ready != 'Y')
      order by rnum
  ) LOOP
    if rec.tv_id is null then
      update tariff set is_ready = stnd.Yes where id = rec.t_id;
      opt_ctr_util.RELEASE_SUBPROCESS_INCREMENT;
    else
      if rec.tv_is_ready = stnd.No and rec.tv_date_from is not null then
        update tariff_data set date_from = null where id = rec.tv_id;
      end if;
      ErrMsg := trf.TARIFF_APPLY(rec.t_id); --approve date: v_local_constants date_from and date_to
      opt_ctr_util.RELEASE_SUBPROCESS_INCREMENT;
    end if;
    if opt_conv.IS_ERROR(ErrMsg) = stnd.Yes then
      sy_process.PROCESS_MESSAGE(substr(ErrMsg, 1, 1), 'Approve failed for "'
        || trf.DOMAIN_TREE_CODE(rec.tariff_domain__oid, 0) || '/' || rec.t_name || '": ' || ErrMsg);
    end if;
    if mod(rec.rnum, CommitInterval) = 0 then
      COMMIT;
    end if;
  END LOOP;
  COMMIT;
  sy_process.PROCESS_MESSAGE(stnd.Information, 'renew_all.sql: Action FINISHED: Approve TARIFFS');
  
  --PA-837, SB-345: Approve Tariff Domain Template
  sy_process.PROCESS_MESSAGE(stnd.Information, 'renew_all.sql: Action STARTED: Approve TEMPLATE TARIFF DOMAINS');
  for rec in (select td.* from tariff_domain td where td.amnd_state = stnd.Active and td.is_personal = 'T' and exists (select 1 from tariff t where t.amnd_state = stnd.Active and t.tariff_domain__oid = td.id and t.is_ready = stnd.No))
  LOOP
    ErrMsg := trf.APPROVE_DOMAIN(rec.id);
    opt_ctr_util.RELEASE_SUBPROCESS_INCREMENT;
    if (substr(ErrMsg, 1, 1) = stnd.Error) then
      sy_process.PROCESS_MESSAGE(substr(ErrMsg, 1, 1), 'Approve failed for '|| rec.code);
    end if;
  END LOOP;
  COMMIT;
  sy_process.PROCESS_MESSAGE(stnd.Information, 'renew_all.sql: Action FINISHED: Approve TEMPLATE TARIFF DOMAINS');
  -->>********************************************End tariff-related objects*********************************************
  
  /*NEVER DELETE THIS*/ opt_ctr_util.RELEASE_SUBPROCESS_END2(ToReject, AppErrorText, AppErrorNumber); --Closes the current process and session if needed, will reject if ToReject was set to stnd.Yes.
END;
/
