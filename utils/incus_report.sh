#!/bin/bash
# Script used in github action to produce a report of puppet successes and failures
# The script was getting to complex to be written in plain yaml.
# Its usefulness is limited somewhat to incus and github action for now.
#
# Notes:
# The file is indented with tabs instead of spaces because heredoc <<- syntax only
# work with tabs.
SUCCESSFUL=0
puppet_server=$(incus list --columns "nd" -f csv | grep \"puppet\" | cut -d',' -f1)
echo
for nodename in $(incus list -c n -f csv); do
	echo -n "### ${nodename}"
	total=$(incus exec ${puppet_server} -- grep 'name="Total"' /var/lib/node_exporter/puppet_report_${nodename}.prom | cut -d' ' -f2)
	failures=$(incus exec ${puppet_server} -- grep 'name="Failure"' /var/lib/node_exporter/puppet_report_${nodename}.prom | cut -d' ' -f2)
	timeout=$(incus exec $nodename -- journalctl -u puppet -p3..3 | grep -i 'command exceeded timeout' | grep -o "([^)]*)" | sort | uniq | wc -l)
	if (( $total == 0 )) || (( $failures - $timeout > 0 )); then
		echo " FAILED"
		cat <<- EOF
			<details><summary>failures</summary>
			<pre><code>$(incus exec $nodename -- journalctl -u puppet -p3..4 | grep -i -v -P '(connection|routes|wrapped|command exceeded timeout)')
			</code></pre></details>
		EOF
		SUCCESSFUL=1
	else
		echo
	fi
	if (( $timeout > 0 )); then
		cat <<- EOF
			<details><summary>timeout</summary>
			<pre><code>$(incus exec $nodename -- journalctl -u puppet -p3..4 | grep -i 'command exceeded timeout')
			</code></pre></details>
		EOF
	fi

	echo
	cat <<- EOF
		<details><summary>apply log</summary>
		<pre><code>$(incus exec $nodename -- journalctl -u puppet)
		</code></pre></details>
	EOF
	echo
	cat <<- EOF
		<details><summary>Puppet report</summary>
		<pre><code>$(incus exec ${puppet_server} -- grep '^puppet_report' /var/lib/node_exporter/puppet_report_${nodename}.prom)
		</code></pre></details>
	EOF
	echo
done
exit $SUCCESSFUL