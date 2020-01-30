#!/bin/bash
#eg:
#hypergrabgb/hypergrabgb.gambas -e 16 -d 9 -q -z "/koko/tmp/gst.sh 0 0 1920 1080 20 200 16 9 0"

# Cattura una cornice dello schermo.
# Da usare per comandare i led quando la gpu è troppo occupata.
# Lo script ha 2 vantaggi:
# 1) Non cattura la parte dello schermo che comunque non verrebbe utilizzata dai led
# 2) effettuando 4 catture invece che un'unica, probabilmente lascia più tempo alla gpu per renderizzare tra una cattura e l'altra (?)

# L'uscita w*h deve essere divisibile per 16, altrimenti gsteamer mette un padding che impedisce a hypergrabgb di parsare correttamente i colori

# Parametri di cattura:
	start_x=$1
	start_y=$2
	in_width=$3
	in_height=$4
	fps=$5
	spessore=$6
# Parametri di uscita
	ow=$7
	oh=$8
# Preview?
	preview=$9
	
# fine parametri

if ! [ $# -eq 9 ] ; then
    echo "ERRORE: Illegal number of parameters"
    echo USO: "$(basename $0)" "start_x start_y in_width in_height fps border_size out_width out_height preview(=1|0)"
    exit
fi

if ! [ $(bc <<< "($ow*$oh)%16")  = 0 ] ; then
	echo ERRORE: \"out_width x out_height\" Has to be integer multiple of 16.
	exit
fi



#  ------------------------------------------------
#  |       |                              |       |
#  |       |           sync 1             |       |
#  |       |                              |       |
#  |       |------------------------------|       |
#  |       |                              |       |
#  |       |                              |       |
#  |sync 0 |           Blank              |sync 2 |
#  |       |                              |       |
#  |       |                              |       |
#  |       |                              |       |
#  |       |------------------------------|       |
#  |       |                              |       |
#  |       |           sync 3             |       |
#  |       |                              |       |
#  ------------------------------------------------

if [ $preview = 1 ] ; then
	outsync="videoconvert ! xvimagesink"
		else
	bufsize=$(($ow*$oh*3)) #<-send one image at a time
	outsync="videoconvert ! video/x-raw,format=RGB ! filesink location=/dev/stdout sync=false buffer-size=$bufsize"
fi

end_x=$(($start_x+$in_width-1))
end_y=$(($start_y+$in_height-1))

scale_by=$(($in_width/$ow))

# Affinchè non ci siano problemi di arrotondamento, è necessatio che larghezza,altezza e bordo siano divisibili per scale_by
# quindi partiamo dall' scale_by che abbiamo trovato e riduciamolo fino a trovare un divisore comune.
MCD_FOUND="FALSE"
for d in $(seq $scale_by -1 1) ; do
	r1=$(bc <<< $in_width%$d)
	r2=$(bc <<< $in_height%$d)
	r3=$(bc <<< $spessore%$d)
	if [ $r1 = "0" ] && [ $r2 = "0" ] && [ $r3 = "0" ] ; then 
		scale_by=$d
		MCD_FOUND="TRUE"
		break
	fi
done


spessore_scalato=$((($spessore)/$scale_by))

scale_method=4 #multitap bilinear

gst-launch-1.0 -q -e videomixer name=mix background=2 \
        sink_0::xpos=0                   sink_0::ypos=0					\
        sink_1::xpos=$spessore_scalato sink_1::ypos=0					\
        sink_2::xpos=$((($end_x-$start_x-($spessore-1))/$scale_by))   sink_2::ypos=0					\
		sink_3::xpos=$spessore_scalato sink_3::ypos=$((($end_y-$start_y-($spessore-1))/$scale_by))		\
            ! videoscale method=$scale_method ! video/x-raw,width=$ow,height=$oh ! $outsync							\
		ximagesrc use-damage=0														\
			startx=$start_x	starty=$start_y											\
			endx=$(($start_x+($spessore-1))) endy=$end_y !								\
			videoscale add-borders=false  method=$scale_method ! video/x-raw,framerate=$fps/1,\
			width=$spessore_scalato!	 mix.sink_0							\
		ximagesrc use-damage=0														\
			startx=$(($start_x+($spessore-1))) starty=$start_y							\
			endx=$(($end_x-($spessore-1))) endy=$(($start_y+($spessore-1))) !				\
			videoscale add-borders=false  method=$scale_method  ! video/x-raw,framerate=$fps/1,\
			height=$spessore_scalato !mix.sink_1									\
		ximagesrc use-damage=0														\
			startx=$(($end_x-($spessore-1))) starty=$start_y endx=$end_x endy=$end_y !	\
			videoscale add-borders=false  method=$scale_method  ! video/x-raw,framerate=$fps/1,\
			width=$spessore_scalato !	mix.sink_2								\
		ximagesrc use-damage=0														\
			startx=$(($start_x+($spessore-1))) starty=$(($end_y-($spessore-1)))				\
			endx=$(($end_x-($spessore-1))) endy=$end_y !								\
			videoscale add-borders=false method=$scale_method  ! video/x-raw,framerate=$fps/1,\
			height=$spessore_scalato !mix.sink_3		
		

