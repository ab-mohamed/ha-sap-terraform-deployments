iscsi-formula:
  pkg.installed:
    - fromrepo: ha-factory

move-iscsi-folder:
  cmd.run:
    - name: mv /srv/salt/iscsi /root/salt/
    - unless: file.path_exists_glob('/root/salt/iscsi')

{% if grains['role'] == 'iscsi_srv' %}
/srv/salt:
  file.absent:
  - require:
    - move-iscsi-folder
{% endif %}
