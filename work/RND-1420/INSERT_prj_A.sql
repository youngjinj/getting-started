INSERT INTO
  prj_A (
    pjct_manage_no,
    pjct_nm,
    pjct_manage_step_code,
    pjct_progrs_sttus_code,
    bsn_progrs_sttus_code,
    bid_propse_progrs_sttus_code,
    pjct_flfl_sttus_code,
    slscg_cnstn_mnno,
    bsn_reprs_appn_at,
    bstgt_cstmr_prscg_idntfc_at,
    bsn_cmptr_info_idntfc_at,
    bsn_corpt_info_idntfc_at,
    dmand_instt_code,
    dmand_instt_nm,
    frst_crtr_id,
    frcrt_dt,
    last_updusr_id,
    lsupd_dt
  )
SELECT
  'A2C5200128374A7AB76CB5AFEE02B16F',
  '2021 대학생 절주서포터즈 활동 물품 제작 및 배포',
  'CM02900020',
  'CM03000010',
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  'Z022921',
  '한국건강증진개발원',
  'batch',
  TO_CHAR(SYS_DATETIME, 'YYYYMMDDHH24MISS'),
  'batch',
  TO_CHAR(SYS_DATETIME, 'YYYYMMDDHH24MISS')
FROM
  db_root
WHERE 
  NOT EXISTS (
    SELECT
      1
    FROM
      prj_A
    WHERE
      pjct_manage_no IN (
        SELECT
          pjct_manage_no
        FROM
          prj_pjct_csorg
        WHERE
          pjct_cause_origin_no = '5-1-2021-Z030668-000001'
          AND pjct_cause_origin_code = 'CM01300004'
      )
  );
