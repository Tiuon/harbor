#!/bin/bash

export PYTHONPATH=$PYTHONPATH:/harbor-migration/db
if [ -z "$DB_USR" -o -z "$DB_PWD" ]; then
    echo "DB_USR or DB_PWD not set, exiting..."
    exit 1
fi

source /harbor-migration/db/alembic.tpl > /harbor-migration/db/alembic.ini

DBCNF="-hlocalhost -u${DB_USR}"

#prevent shell to print insecure message
export MYSQL_PWD="${DB_PWD}"

if [[ $1 = "help" || $1 = "h" || $# = 0 ]]; then
    echo "Usage:"
    echo "backup                perform database backup"
    echo "restore               perform database restore"
    echo "up,   upgrade         perform database schema upgrade"
    echo "test                  test database connection"
    echo "h,    help            usage help"
    exit 0
fi

# if [[ ( $1 = "up" || $1 = "upgrade" ) && ${SKIP_CONFIRM} != "y" ]]; then
#     echo "Please backup before upgrade."
#     read -p "Enter y to continue updating or n to abort:" ans
#     case $ans in
#         [Yy]* )
#             ;;
#         [Nn]* )
#             exit 0
#             ;;
#         * ) echo "illegal answer: $ans. Upgrade abort!!"
#             exit 1
#             ;;
#     esac
# fi

echo 'Trying to start mysql server...'
chown -R 10000:10000 /var/lib/mysql
mysqld &
echo 'Waiting for MySQL start...'
for i in {60..0}; do
    mysqladmin -u$DB_USR -p$DB_PWD processlist >/dev/null 2>&1
    if [ $? = 0 ]; then
        break
    fi
    sleep 1
done
if [ "$i" = 0 ]; then
    echo "timeout. Can't run mysql server."
    if [[ $1 = "test" ]]; then
        echo "DB test failed."
    fi
    exit 1
fi
if [[ $1 = "test" ]]; then
    echo "DB test passed."
    exit 0
fi

key="$1"
case $key in
up|upgrade)
    VERSION="$2"
    if [[ -z $VERSION ]]; then
        VERSION="head"
        echo "Version is not specified. Default version is head."
    fi
    echo "Performing upgrade ${VERSION}..."
    if [[ $(mysql $DBCNF -N -s -e "select count(*) from information_schema.tables \
        where table_schema='registry' and table_name='alembic_version';") -eq 0 ]]; then
        echo "table alembic_version does not exist. Trying to initial alembic_version."
        mysql $DBCNF < ./alembic.sql
        #compatible with version 0.1.0 and 0.1.1
        if [[ $(mysql $DBCNF -N -s -e "select count(*) from information_schema.tables \
            where table_schema='registry' and table_name='properties'") -eq 0 ]]; then
            echo "table properties does not exist. The version of registry is 0.1.0"
        else
            echo "The version of registry is 0.1.1"
            mysql $DBCNF -e "insert into registry.alembic_version values ('0.1.1')"
        fi
    fi
    alembic -c /harbor-migration/db/alembic.ini current
    alembic -c /harbor-migration/db/alembic.ini upgrade ${VERSION}
    rc="$?"
    alembic -c /harbor-migration/db/alembic.ini current	
    echo "Upgrade performed."
    exit $rc	
    ;;
backup)
    echo "Performing backup..."
    mysqldump $DBCNF --add-drop-database --databases registry > /harbor-migration/backup/registry.sql
    rc="$?"
    echo "Backup performed."
    exit $rc
    ;;
export)
    echo "Performing export..."
    /harbor-migration/db/export --dbuser ${DB_USR} --dbpwd ${DB_PWD} --exportpath ${EXPORTPATH}
    rc="$?"
    echo "Export performed."
    exit $rc
    ;;
mapprojects)
    echo "Performing map projects..."
    /harbor-migration/db/mapprojects --dbuser ${DB_USR} --dbpwd ${DB_PWD} --mapprojectsfile ${MAPPROJECTFILE}
    rc="$?"
    echo "Map projects performed."
    exit $rc
    ;;
restore)
    echo "Performing restore..."
    mysql $DBCNF < /harbor-migration/db/backup/registry.sql
    rc="$?"
    echo "Restore performed."
    exit $rc
    ;;
*)
    echo "unknown option"
    exit 0
    ;;
esac