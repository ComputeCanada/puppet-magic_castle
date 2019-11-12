archs=({{ with tree "cvmfs" | explode -}}
{{range $key, $value := . -}}
{{ $value.rsnt_arch }} {{ end -}} {{ end -}})
if [[ " ${archs[@]} " =~ " pni " ]]; then
    export RSNT_ARCH="pni"
elif [[ " ${archs[@]} " =~ " avx " ]]; then
    export RSNT_ARCH="avx"
elif [[ " ${archs[@]} " =~ " avx2 " ]]; then
    export RSNT_ARCH="avx2"
elif [[ " ${archs[@]} " =~ " avx512 " ]]; then
    export RSNT_ARCH="avx512"
fi
