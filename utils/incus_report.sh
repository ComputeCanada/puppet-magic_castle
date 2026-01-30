#!/bin/bash
# Script used in github action to produce a report of puppet successes and failures
# The script was getting to complex to be written in plain yaml.
# Its usefulness is limited somewhat to incus and github action for now.
#
# Notes:
# The file is indented with tabs instead of spaces because heredoc <<- syntax only
# work with tabs.
SUCCESSFUL=0
for nodename in $(incus list -c n -f csv); do
	echo -n "### ${nodename}" 
	failures=$(incus exec mgmt1 -- cat /var/lib/node_exporter/puppet_report_${nodename}.prom | grep 'name="Failure"' | cut -d' ' -f2)
	if (( $failures > 0 )); then
		echo " FAILED"
		cat <<- EOF
			#### failures
			<details><pre><code>$(incus exec $nodename -- journalctl -u puppet -p3..4 | grep -i -v -P '(connection|routes|wrapped)')
			</code></pre></details>
		EOF
		SUCCESSFUL=1
	else
		echo
	fi

	echo
	cat <<- EOF
		#### successes
		<details><pre><code>$(incus exec $nodename -- journalctl -u puppet -p5..5)
		</code></pre></details>
	EOF

	echo
	cat <<- EOF
		#### Puppet report
		<details><pre><code>$(incus exec mgmt1 -- cat /var/lib/node_exporter/puppet_report_${nodename}.prom | grep '^puppet_report')
		</code></pre></details>
	EOF
done
exit $SUCCESSFUL