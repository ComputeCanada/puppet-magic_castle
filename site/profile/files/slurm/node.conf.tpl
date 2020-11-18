{{ range service "slurmd" -}}
{{ scratch.MapSet "cpus" (.ServiceMeta.cpus | parseInt | printf "%02d" ) .ServiceMeta.cpus -}}
{{ scratch.MapSet "mem" (.ServiceMeta.realmemory | parseInt | printf "%10d" ) .ServiceMeta.realmemory -}}
{{ scratch.MapSet "gpus" (.ServiceMeta.gpus | parseInt | printf "%02d" ) .ServiceMeta.gpus -}}
{{ end -}}

{{ range $index, $value := scratch.MapValues "cpus" -}}{{ scratch.Set ($value | printf "wcpus_%s") (add $index 1)}}{{ end -}}
{{ range $index, $value := scratch.MapValues "gpus" -}}{{ scratch.Set ($value | printf "wgpus_%s") (add $index 1)}}{{ end -}}
{{ range $index, $value := scratch.MapValues "mem" -}}{{ scratch.Set ($value | printf "wmem_%s") (add $index 1)}}{{ end -}}

{{ range service "slurmd" -}}
NodeName={{.Node}} CPUs={{.ServiceMeta.cpus}} RealMemory={{.ServiceMeta.realmemory}} {{if gt (parseInt .ServiceMeta.gpus) 0}}Gres=gpu:{{.ServiceMeta.gpus}}{{end}} Weight={{scratch.Get (.ServiceMeta.gpus | printf "wgpus_%s") }}{{scratch.Get (.ServiceMeta.realmemory | printf "wmem_%s") }}{{scratch.Get (.ServiceMeta.cpus | printf "wcpus_%s") }}
{{ end -}}