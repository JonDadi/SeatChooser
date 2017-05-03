

-- Höfundur: Jón Daði Jónsson 2014.
-- Kennari: Sigurður R. Ragnarsson.
-- Þetta er algorithmi sem raðar fólki og hópum í sæti með FreshAir_v2 gagnagrunninum.
-- TODO listinn er í Bókun Hópa hlutanum.

/*
***********************************************************************************************************************
*  				     	                      --> Bókun Einstaklings <-- 									     	  *
*																													  *
* Röð aðgerða:																										  *
* 1)	bookPerson(flight_number, flight_date, booking_number, personID, priceCat) 				-> Stored Procedure	  *
* 2)		getSeatID(flight_number, flight_date) 								   				-> Function			  *
* 3)			Carrier(flight_number, flight_date)								   				-> Function			  *
* 4)			determineSeatPosition(flight_number, flight_date, plane_id) 		   			-> Function			  *
* 5)			checkIfSeatPlacementIsFull(flight_number, flight_date, plane_id, seatplacement) -> Function 	      *
* 6)				occupiedSeats 																-> View				  *
*																													  *
***********************************************************************************************************************
*/


/*  
 * Stored Procedure sem gengur frá bókun fyrir einstakling.
 */
delimiter $$
drop procedure if exists bookPerson $$
create procedure bookPerson(flight_number char(5), flight_date date, booking_number int, pID varchar(35), priceCat int)
begin
	declare passengerName varchar(55);
	declare prefSeatID int; -- Sætið sem farþeginn fer í.

	select personName into passengerName from persons where personID = pID;
	set prefSeatID = getSeatID(flight_number,flight_date); -- Nær í sætið sem farþeginn á að bókast í.

	insert into Seating(personID,personName,PriceID,seatID,bookingNumber) 
	values(pID,passengerName,priceCat,prefSeatID,booking_number);
	
end $$


/*  
 * Fallið finnur ID á sæti sem farþeginn á að fara í.
 */
delimiter $$
drop function if exists getSeatID $$ 
create function getSeatID(flight_number char(5),flight_date date)
returns int
begin
declare optimalSeatID int;

declare plane_id char(6);
set plane_id = Carrier(flight_number,flight_date);

select seatID into optimalSeatID
from Seats
	where Seats.aircraftID = plane_id
	and Seats.seatPlacement = determineSeatPosition(flight_number,flight_date, plane_id) -- Hér finnur fallið í hvernig sæti farþeginn fer í (Gluggasæti, Gangsæti, Miðjusæti).
	and Seats.rowNumber < findNumberOfSeatRows(flight_number, flight_date, plane_id) -- Passar að sætið sé ekki hluti af hópsvæðinu.
	and seatID not in (select seatID from occupiedSeats -- Finnur sætin sem eru þegar bókuð.
					   where flightNumber = flight_number 
				       and flightDate = flight_date 
					   and aircraftID = plane_id)
	order by seatID limit 1; -- Velur bara eitt sæti.

return optimalSeatID;
end $$


/*  
 * Fallið finnur hvaða flugvél flýgur ákveðið flug
 */
delimiter $$
drop function if exists Carrier $$
create function Carrier(flight_number char(5),flight_date date)
returns char(6)
deterministic
begin
	declare plane_id char(6);

	select aircraftID into plane_id 

	from Flights where flightNumber = flight_number and flightDate = flight_date;
	
	return plane_id;
end $$


/*  
 * Þetta fall ákveður hvernig sæti farþeginn fær í vélinni (Gluggasæti, Miðjusæti, Gangsæti).
 */
delimiter $$
drop function if exists determineSeatPosition $$
create function determineSeatPosition(flight_number char(5),flight_date date, plane_id char(6))
returns char(1)
begin
	declare seatPosition char(1);  -- Breytan sem segjir til um staðsetningu á sæti í vélinni. Gluggasæti(W), Gangsæti(A), Miðjusæti(M).
	declare windowFull tinyint(1); -- Verður 1 ef öll gluggasæti eru tekin.
	declare aisleFull tinyint(1);  -- Verður 1 ef öll gangsæti eru tekin.

	set seatPosition = 'w'; -- Setur staðsetninguna fyrst í gluggasæti þar sem þau hafa forgang.
	set windowFull = checkIfSeatPlacementIsFull(flight_number, flight_date, plane_id, "w"); -- Athugar hvort öll gluggasæti í vélinni séu bókuð.
	
	if(windowFull = 1) -- Gluggasætin eru öll bókuð,  staðsetning verður þá gangsæti.
		then set seatPosition = "a";
	end if;

	if(seatPosition = "a") -- Athugar hvort gangsætin séu full í hvert skipti sem sett er í aisle sæti.
		then set aisleFull = checkIfSeatPlacementIsFull(flight_number, flight_date, plane_id, "a"); -- Athugar hvort gangsætin séu full
	end if;

	if(aisleFull = 1) -- Bæði gluggasætin og gangsætin eru full, staðsetningin verður þá miðjusæti.
		then set seatPosition ="m";
	end if;
	
	return seatPosition; -- Skilar tegund af sæti sem farðþeginn verður settur í.

end $$

/*
 * Fall sem athugar hvort sæti séu laus í ákveðinum sætaflokki.
 * Fallið telur öll lausu sætin,  ef útkoman er 0 þá skilar fallið true.
 */
delimiter $$
drop function if exists checkIfSeatPlacementIsFull $$
create function checkIfSeatPlacementIsFull(flight_number char(5), flight_date date, plane_id char(6), seatplacement char(1))
returns tinyint(1)
begin
	declare isFull tinyint(1);

	if(select Count(seatID) from Seats
		where Seats.aircraftID = plane_id
		and Seats.seatPlacement = seatplacement -- Hér er sætaflokkurinn ákveðinn.
		and seatID not in (select seatID from occupiedSeats -- Passar að sætið sé ekki nú þegar bókað.
					   where flightNumber = flight_number 
				       and flightDate = flight_date 
					   and aircraftID = plane_id)) = 0
		then set isFull = 1; -- Engin sæti eru laus og því er isFull sett í true(1).
	else set isFull = 0;	 -- Einhver sæti eftir og þá er breytan sett í false(0).
	end if;
	return isFull;
end $$


/*
 * View sem finnur bókuð sæti.
 */
delimiter $$
drop view if exists occupiedSeats;
create view occupiedSeats
as
	select S.seatID,F.flightNumber,F.flightDate,S.aircraftID 
	from Seats S
	inner join Seating SE on S.seatID = SE.seatID
	inner join Bookings B on SE.bookingNumber = B.bookingNumber
	inner join Flights F on B.flightCode = F.flightCode;







/*
***********************************************************************************************************************
*  				     	                        --> Bókun Hóps <-- 									     	          *
*																													  *
* Röð aðgerða:																										  *
* 1)	SeatGroup(flight_number, flight_date, groupID, bookingNumber, prizeID)	-> Stored Procedure	  				  *
* 2)		Carrier(flight_number, flight_date)	  								-> Function							  *
* 3)		GetGroupSize(groupID)	  											-> Function							  *
* 4)		SetAvailableGroupSeatsInTemp(flight_number, flight_date, planeID)	-> Stored Procedure  				  *
* 5)			FindNumberOfSeatRows(flight_number, flight_date, plane_id) 		-> Function							  *
* 6)		SetGroupIntoTemp(groupID)       									-> Stored Procedure	                  *
* 7)		GetAvailableRow(groupSize)											-> Function							  *
* 8)			LastRowAvailable()												-> Function				   		      *
* 9)			FirstRowAvailable()												-> Function							  *
* 10)			GetAvailableSeatsInRow(rowToCheck)								-> Function							  *
* 11)			SetSeatsToUseIntoTemp(rowToUse, groupSize)						-> Stored Procedure		              *
*																													  *
***********************************************************************************************************************

TODO LIST:
  1)
	Núna er bara hægt að setja inn hóp sem er jafn stór eða minni og fjöldi sæta í einni sætaröð í flugvélinni,  
	það væri möguleiki að bæta það með því að laga fallið SetSeatsToUseIntoTemp.  Láta það setja restina af fólkinu í sætaröðina rowToUse+1. 
	Þetta er hægt því ef hópurinn er að taka heila sætaröð þá ætti næsta röð líka að vera tóm nema að flugvélin sé full.
  
  2)
	Fall sem endurraðar fólki sem var svo óheppið að lenda með miðjusæti,  rétt fyrir flug þá eru líklega einhver glugga eða gangsæti laus í vélinni
	vegna brotfalla eða þá afgangs sæti í hópasvæðinu. Það væri hægt að setja alla sem eru ekki í hópasvæðinu og sem eru í miðjusæti í temp töflu,
	og síðan setja öll lausu sætin sem eru ekki miðjusæti í aðra temp töflu og setja síðan fólkið í fyrri temp töfluna í sætin sem fara í seinni töfluna.

  3) 
	Athuga hvernig algorithminn virkar með flugvélar sem eru með fleiri en eitt deck.
  
  4)
	Laga hvernig temp töflurnar eru búnar til.
	
*/


/*  
 * Fall sem setur hóp í sæti, fallið leitar af sætaröð innan hópsvæðisins sem inniheldur sæti sem eru jafn mörg eða fleiri en stærð hópsins.
 */
delimiter $$
drop procedure if exists seatGroup$$
create procedure seatGroup(flight_number char(5), flight_date date, groupID int, bookingNumber int, prizeID int)
begin

declare indexer int;		-- Loopu indexer.
declare pID varchar(35);    -- Kennitala.
declare pName varchar(55);  -- Nafn.
declare pPrice varchar(55); -- Verðflokkur.
declare pSeatID int; 		-- Sæta ID.
declare groupSize int;		-- Stærð hóps.
declare planeID char(6);	-- Flugvéla ID.
declare rowToUse int;		-- Sætaröð sem hópurinn er settur í.

set indexer = 1; -- Index verður að byrja á 1.
set planeID = carrier(flight_number, flight_date); -- Finnur flugvéla ID.
set groupSize = getGroupSize(groupID);  -- Finnur fjölda í hóp.

call setAvailableGroupSeatsInTemp(flight_number, flight_date, planeID); -- Setur öll sæti sem eru laus í hópasvæðinu inn í temp töflu.
call setGroupIntoTemp(groupID); -- Setur hópinn í temp töfluna fyrir meðlimi hóps.

set rowToUse = getAvailableRow(groupSize); -- Finnur hvaða sætaröð hópurinn á að fara í.
call setSeatsToUseIntoTemp(rowToUse, groupSize); -- Setur sætin sem hópurinn á að fara í, inn í temp töfluna.

	while indexer <= groupSize DO -- While lykkja sem keyrir jafn oft og fjöldi meðlima í hópnum.

		-- Hér eru rétt gildi sett inn í breyturnar sem eru síðan notaðar til þess að inserta inn í Seats.
		select seatID into pSeatID 
		from seatsToUse
		where seatIndex = indexer;

		select personID into pID
		from groupMembers 
		where numberInGroup = indexer;

		select personName into pName
		from groupMembers
		where numberInGroup = indexer;

		insert into Seating(personID,personName,PriceID,seatID,bookingNumber) 
		values(pID, pName, priceID, pSeatID, bookingNumber);
		
		set indexer = indexer + 1; -- Indexerinn hækkar sem þýðir að næsta manneskja í hópnum verður valin næst.

	end while;

end$$

/*  
 * Fall sem finnur hversu margir eru í tilteknum hóp.
 */
delimiter $$
drop function if exists getGroupSize $$
create function getGroupSize(groupid int)
returns int
begin

	declare groupSize int;

	select count(personID) into groupSize 
		from persons 
		where groupNumber = groupid;
	return groupSize;
end $$



/*  
 * Stored Procedure sem setur öll laus sæti innan hópsvæðisins inn í temp töfluna GroupSeats
 */
delimiter $$
drop procedure if exists setAvailableGroupSeatsInTemp$$
create procedure setAvailableGroupSeatsInTemp(flight_number char(5), flight_date date, plane_id char(6))
begin

	truncate table groupSeats; -- Hreinsar töfluna 

	insert into groupSeats(seatID, rowNumber, seatNumber, seatPlacement, deck)
	select seatID, rowNumber, seatNumber, seatPlacement, deck from Seats
	where Seats.aircraftID = plane_id
	and Seats.rowNumber > findNumberOfSeatRows(flight_number, flight_date, plane_id) -- Passar að sætin séu bara innan hópsvæðisins.
	and seatID not in (select seatID from occupiedSeats -- Passar að sætin séu ekki tekin.
					   where flightNumber = flight_number 
				       and flightDate = flight_date 
					   and aircraftID = plane_id);
end$$


/*  
 * Fall sem finnur sætaröð sem skiptir vélinni í tvo parta,  einstaklingssvæði og hópasvæði. 30% af aftari parti vélarinnar fer í hópasvæði.
 */
delimiter $$
drop function if exists findNumberOfSeatRows$$
create function findNumberOfSeatRows(flight_number char(5),flight_date date, plane_id char(6))
returns int
begin

declare numberOfRows int;

select count(distinct rowNumber) into numberOfRows from Seats where aircraftID = plane_id; -- Distinct tekur duplicates í burtu svo það sé hægt að telja sætaraðirnar.

return numberOfRows - (numberOfRows * 0.3); -- Hér er hægt að stilla hversu mörg prósent af vélinni fer í hópasvæðið (Breyta 0.3 í eitthvað annað).
end $$


/*  
 * Stored Procedure sem setur meðlimi í tilteknum hóp inn í temp töfluna groupMembers.
 */
delimiter $$
drop procedure if exists setGroupIntoTemp$$
create procedure setGroupIntoTemp(groupID int(11))
begin
	
	truncate table groupMembers; -- Hreinsar fyrri hóp úr töflunni.

	insert into groupMembers(personID, personName, groupID)
	select personID, personName, groupNumber
	from persons
	where groupNumber = groupID;
end$$

/*  
 * Fall sem finnur hvaða sætaröð væri best að setja hóp að ákveðinni stærð í.
 * Fallið finnur hvar hópasvæðið byrjar og leitar í öllum sætaröðum í því sem eru ekki fullar.
 * Fallið skilar síðan sætaröð sem hópurinn ætti að komast í.
 */
delimiter $$
drop function if exists getAvailableRow$$
create function getAvailableRow(groupSize int)
returns int
begin

declare rowToCheck int; -- Sætaröðin sem fallið er að athuga, byrjar á fyrstu sætaröðinni í hópasvæðinu.
declare seatsLeft int;	-- Fjöldi sæta sem er laus í sætaröð.
declare lastRow int;	-- Seinasta röðin í flugvélinni.
declare rowToUse int;	-- Sætaröðin sem hópurinn fer í.

set lastRow = lastRowAvailable();	  -- Finnur seinustu sætaröðina í vélinni.
set rowToCheck = firstRowAvailable(); -- Finnur fyrstu sætaröðina sem er notuð fyrir hópa.
set rowToUse = 0;

	while rowToUse = 0 DO -- Keyrir einu sinni fyrir hverja röð sem er tekin fyrir hópa.

		 set seatsLeft = GetAvailableSeatsInRow(rowToCheck); -- Athugar hvað það eru mörg sæti laus í ákveðinni röð.

		 if(seatsLeft = groupSize)
			 then set rowToUse = rowToCheck; -- Sætin sem fundust í röðinni eru akkúrat jafn mörg og meðlimir hópsins. (best case scenario)
		 
		 elseif(seatsLeft > groupSize)
			 then set rowToUse = rowToCheck; -- Sætin sem fundust í röðinni eru fleiri en meðlimir hópsins.

		else set rowToCheck = rowToCheck + 1;
		end if;
	end while;

	return rowToUse;
end$$


/*  
 * Fall sem finnur einustu sætaröð í flugvélinni sem er valin í temp töflunni.
 */
delimiter $$
drop function if exists lastRowAvailable$$
create function lastRowAvailable()
returns int
begin

	declare lastRow int;
	select max(rowNumber) into lastRow from groupSeats;
	return lastRow;
end$$


/*  
 * Fallið finnur fyrstu sætaröð í hópasvæði í flugvélinni sem er valin í temp röflunni..
 */
delimiter $$
drop function if exists firstRowAvailable$$
create function firstRowAvailable()
returns int
begin

	declare firstrow int;
	select min(rowNumber) into firstrow from groupSeats;
	return firstrow;
end$$


/*  
 * Fall sem finnur hversu mörg sæti eru laus í ákveðinni sætaröð.
 */
delimiter $$
drop function if exists GetAvailableSeatsInRow$$
create function GetAvailableSeatsInRow(rowNum int)
returns int
begin
	declare numberOfSeats int;

	select count(seatID) into numberOfSeats from groupSeats -- Telur sætin og setur útkomuna í numberOfSeats.
	where rowNumber = rowNum;

	return numberOfSeats;
end$$

/*  
 * Fall sem finnur sæti fyrir hóp úr ákveðinni sætaröð.  Fallið tekur bafa jafn mörg sæti og meðlimir í hópnum.
 * Það væri hægt að bæta inn einhverju falli sem yrði kallað á hérna til þess að geta sett hópa sem eru stórir í margar sætaraðir.
 */
delimiter $$
drop procedure if exists setSeatsToUseIntoTemp$$
create procedure setSeatsToUseIntoTemp(rowID int, groupSize int)
begin
	
	truncate table seatsToUse; -- Hreinsar töfluna.

	insert into seatsToUse(seatID, rowNumber, seatNumber, seatPlacement, deck)
	select seatID, rowNumber, seatNumber, seatPlacement, deck 
	from groupSeats
	where rowNumber = rowID
	order by seatID limit groupSize; -- Tekur bara jafn mörg sæti og meðlimir í hópnum.


end$$

/* ++++++++++++++++++++++++++++++++++++++++++++++++ TEMP TÖFLUR ++++++++++++++++++++++++++++++++++++++++++++++++ */

/*  
 * GroupSeats taflan heldur utanum öll laus sæti í hópasvæði í ákveðinni flugvél.
 * Þessi tafla er notuð sem temp tafla þó hún sé það ekki,  það er gert því ég þarf að komast í hana oftar en einu sinni í SeatGroup fallinu.
 */
drop table if exists groupSeats; 
CREATE TABLE groupSeats (
	seatIndex int auto_increment Primary key,
	seatID int NOT NULL,
	rowNumber int NOT NULL,
	seatNumber char(1) NOT NULL,
	seatPlacement varchar(15),
	deck char(5)
);

/*  
 * Þessi tafla heldur utanum upplýsingar um meðlimi hóps.
 */
CREATE TEMPORARY TABLE groupMembers(
	numberInGroup int auto_increment Primary key,
	personID varchar(35),
	personName varchar(75),
	groupID int(11)
);

/*  
 * Í þessari temp töflu eru sætin geymd sem hafa verið valin fyrir ákveðinn hóp.
 * Taflan heldur aðeins utanum sæti fyrir einn hóp í einu.
 */
CREATE TEMPORARY TABLE seatsToUse(
	seatIndex int auto_increment Primary key,
	seatID int NOT NULL,
	rowNumber int NOT NULL,
	seatNumber char(1) NOT NULL,
	seatPlacement varchar(15),
	deck char(5)
);


