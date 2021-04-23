# backup

mkdir -p $HOME/bin
mkdir -p $HOME/GitHub

cd $HOME/GitHub
git clone https://github.com/youngjinj/backup.git backup

cd $HOME/GitHub/backup/bin
chmod +x *.sh

./rsync.sh $HOME/GitHub/backup/bin $HOME

./rsync.sh $HOME/GitHub/backup/.vscode $HOME/GitHub/cubrid

