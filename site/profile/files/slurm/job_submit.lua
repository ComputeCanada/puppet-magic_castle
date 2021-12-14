function slurm_job_submit(job_desc, part_list, submit_uid)
  job_desc.selinux_context = "user_u:user_r:user_t:s0"
  return slurm.SUCCESS
end

function slurm_job_modify(job_desc, job_rec, part_list, modify_uid)
  return slurm.SUCCESS
end

slurm.log_info("initialized")
return slurm.SUCCESS

