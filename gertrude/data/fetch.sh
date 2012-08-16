#!/bin/bash
#
# this fetches the TAC database at www.mulliner.org, only fetching the CSV files and dumping them all in the same dir

wget -r -np -nd -nH -Acsv http://www.mulliner.org/tacdb/feed/
