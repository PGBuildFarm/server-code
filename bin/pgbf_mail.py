#!/usr/bin/python

import smtplib
import psycopg2
import psycopg2.extras

dbcon = psycopg2.connect('dbname=%s' % ('pgbfprod',))

cur = dbcon.cursor(cursor_factory=psycopg2.extras.DictCursor)
cur.execute("SELECT * FROM pending()");

fromaddr = "pgbuildfarm@brentalia.postgresql.org"
#toaddrs = ['ashaw@commandprompt.com']
toaddrs = [ "pgbuildfarm@lists.commandprompt.com"]

if cur.rowcount >= 1:
    
    email = "Subject: PGBuildfarm Outstanding Requests\r\n"
    email += ("From: %s\r\nTo: %s\r\n\r\n"
           % (fromaddr, ", ".join(toaddrs)))
    
    email += "\nCurrent pending Buildfarm requests: \n"
    
    for row in cur.fetchall():
        
        email += """%s(%s) - %s(%s) on %s\n - compiler: %s v%s\n - pending since: %s\n\n""" \
            % (
                row['owner'], 
                row['owner_email'], 
                row['operating_system'],
                row['os_version'],
                row['architecture'],
                row['compiler'],
                row['compiler_version'],
                row['status_ts'].strftime("%A %b %e, %r")
            ) 
    
    mserv = smtplib.SMTP('localhost')
    mserv.sendmail(
        fromaddr,
        toaddrs,
        email
    )
