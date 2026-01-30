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
			<details>
			```
			$(incus exec $nodename -- journalctl -u puppet -p3..4 | grep -i -v -P '(connection|routes|wrapped)')
			```
			</details>
		EOF
		SUCCESSFUL=1
	else
		echo
	fi

	cat <<- EOF
		#### successes
		<details>
		```
		$(incus exec $nodename -- journalctl -u puppet -p5..5)
		```
		</details>
	EOF

	cat <<- EOF
		#### Puppet report"
		<details>
		```
		$(incus exec mgmt1 -- cat /var/lib/node_exporter/puppet_report_${nodename}.prom | grep '^puppet_report')
		```
		</details>
	EOF
done
exit $SUCCESSFUL