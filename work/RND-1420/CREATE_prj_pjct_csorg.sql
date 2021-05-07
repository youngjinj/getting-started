CREATE TABLE [prj_pjct_csorg] (
  [pjct_manage_no] CHARACTER VARYING(64) NOT NULL,
  [pjct_cause_origin_no] CHARACTER VARYING(64) NOT NULL,
  [pjct_cause_origin_code] CHARACTER VARYING(30),
  [miso_exmnt_de] CHARACTER VARYING(8),
  [miso_avrg_addi_scre] NUMERIC(9, 2),
  [miso_exmnt_grad_code] CHARACTER VARYING(30),
  [intbs_at] CHARACTER VARYING(1),
  [intbs_exarq_cnstn_mnno] CHARACTER VARYING(10),
  [intbs_exarq_dt] CHARACTER VARYING(14),
  [intbs_appn_dt] CHARACTER VARYING(14),
  [intbs_exmnt_cnstn_mnno] CHARACTER VARYING(10),
  [intbs_excl_cnstn_mnno] CHARACTER VARYING(10),
  [intbs_excl_dt] CHARACTER VARYING(14),
  [bidpt_confm_dt] CHARACTER VARYING(14),
  [bidpt_confm_cnstn_mnno] CHARACTER VARYING(10),
  [frst_crtr_id] CHARACTER VARYING(10),
  [frcrt_dt] CHARACTER VARYING(14) DEFAULT TO_CHAR(SYS_DATETIME, 'YYYYMMDDHH24MISS'),
  [last_updusr_id] CHARACTER VARYING(10),
  [lsupd_dt] CHARACTER VARYING(14) DEFAULT TO_CHAR(SYS_DATETIME, 'YYYYMMDDHH24MISS'),
  CONSTRAINT [prj_pjct_csorg_pk] PRIMARY KEY ([pjct_manage_no], [pjct_cause_origin_no]),
  INDEX [prj_pjct_csorg_01_ix] ([pjct_cause_origin_no], [pjct_cause_origin_code])
) COLLATE utf8_bin;