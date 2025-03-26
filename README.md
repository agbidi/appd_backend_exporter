# appd_backend_exporter
A script that extracts backends of AppDynamics Applications via the AppD API

Usage: appd_backend_exporter.sh [-h] [-v] -c config_file

A script that does backups and migrations of AppDynamics Configuration.

Available options:

-h, --help        Print this help and exit<br>
-v, --verbose     Print script debug info<br>
-c, --config      Path to config file<br>

Example:

./appd_backend_exporter.sh -c appd_prod.cfg<br>

Content of the config file:

appd_src_url='http://src_account.saas.appdynamics.com:443' # appd source controller url<br>
appd_src_account='src_account' # appd account<br>
appd_src_api_user='<user>' # appd api username<br>
appd_src_api_password='<password>' # appd api password for basic auth<br>
appd_api_secret='<secret>' # appd api secret for oauth <br>
appd_src_proxy='' # http proxy<br>
application_names='.\*' # application names regex<br>
backend_type='.\*' # backend type regex. ex for DB only: JDBC|ADODOTNET|Cassandra <br>
skip_thread_tasks='false' # set true to skip searching backends in thread tasks (faster but less reliable) <br>
output_file='out.csv' # output file <br>
