{{ range service "slurmctld" -}}
SlurmctldHost={{ .Node }}({{ .Address }})
SlurmctldPort=6817
{{ end -}}

## Accounting
{{ range service "slurmdbd" -}}
AccountingStorageHost={{ .Node }}
{{ end -}}

{{ if service "slurmdbd" -}}
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageTRES=gres/gpu,cpu,mem
AccountingStorageEnforce=associations
JobAcctGatherType=jobacct_gather/cgroup
JobAcctGatherFrequency=task=30
JobAcctGatherParams=NoOverMemoryKill,UsePSS
{{ end -}}
