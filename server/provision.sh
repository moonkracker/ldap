#!/bin/bash

set -ex
ulimit -n 1024

if [ ! -f /data/lib/ldap/DB_CONFIG ]; then
    if [ -z "$LDAP_ROOT_PASSWORD" -o -z "$LDAP_MANAGER_PASSWORD" ]; then
        echo "Need LDAP_ROOT_PASSWORD and LDAP_MANAGER_PASSWORD"
        exit
    fi
    
    cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
    chown ldap. /var/lib/ldap/DB_CONFIG

    /usr/sbin/slapd -h "ldap:/// ldaps:/// ldapi:///" -g ldap -u ldap -d $DEBUG_LEVEL &
    slapd_pid=$!
    sleep 10

    ROOT_PWD=$(slappasswd -s $LDAP_ROOT_PASSWORD)
    sed -i "s+%CHANGE_THIS_TO_USER_PASSWD%+${ROOT_PWD//+/\\+}+" /root/ldaprootpasswd.ldif
    ldapmodify -Y EXTERNAL -H ldapi:/// -f /root/ldaprootpasswd.ldif

    ldapadd -Y EXTERNAL -H ldapi:/// -D "cn=config" -f /etc/openldap/schema/cosine.ldif
    ldapadd -Y EXTERNAL -H ldapi:/// -D "cn=config" -f /etc/openldap/schema/nis.ldif
    ldapadd -Y EXTERNAL -H ldapi:/// -D "cn=config" -f /etc/openldap/schema/inetorgperson.ldif
    
    MANAGER_PWD=$(slappasswd -s $LDAP_MANAGER_PASSWORD)
    sed -i "s+%CHANGE_TO_LDAP_MANAGER_PASSWORD%+${MANAGER_PWD//+/\\+}+" /root/ldapdomain.ldif
    ldapmodify -Y EXTERNAL -H ldapi:/// -f /root/ldapdomain.ldif

    ldapadd -x -D cn=Manager,dc=devopslab,dc=com -w $LDAP_MANAGER_PASSWORD -f /root/baseldapdomain.ldif
    ldapadd -x -D cn=Manager,dc=devopslab,dc=com -w $LDAP_MANAGER_PASSWORD -f /root/ldapgroup.ldif

    USER_PWD=$(slappasswd -s $LDAP_USER_PASSWORD)
    sed -i "s+%CHANGE_TO_LDAP_USER_PASSWORD%+${USER_PWD//+/\\+}+" /root/ldapuser.ldif
    ldapadd -x -D cn=Manager,dc=devopslab,dc=com -w $LDAP_MANAGER_PASSWORD -f  /root/ldapuser.ldif

    kill "$slapd_pid"
    wait "$slapd_pid"

    mkdir -p /data/lib /data/etc
    cp -ar /var/lib/ldap /data/lib
    cp -ar /etc/openldap /data/etc
fi
    
rm -rf /var/lib/ldap && ln -s /data/lib/ldap /var/lib/ldap
rm -rf /etc/openldap && ln -s /data/etc/openldap /etc/openldap

pushd /var/lib/ldap
db_recover -v -h .
db_upgrade -v -h . *.bdb
db_checkpoint -v -h . -1
chown -R ldap: .
popd
exec /usr/sbin/slapd -h "ldap:/// ldaps:/// ldapi:///" -u ldap -d $DEBUG_LEVEL

sleep infinity