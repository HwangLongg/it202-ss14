-- bài 1: quản lý chuyển tiền
create table accounts (
    account_id int primary key auto_increment,
    account_name varchar(50),
    balance decimal(10,2)
);

insert into accounts (account_name, balance) values 
('nguyễn văn an', 1000.00),
('trần thị bảy', 500.00);

delimiter //
create procedure sp_transfer_money(
    in from_account int,
    in to_account int,
    in amount decimal(10,2)
)
begin
    declare current_balance decimal(10,2);
    start transaction;
    select balance into current_balance from accounts where account_id = from_account;
    if current_balance >= amount then
        update accounts set balance = balance - amount where account_id = from_account;
        update accounts set balance = balance + amount where account_id = to_account;
        commit;
    else
        rollback;
    end if;
end //
delimiter ;

-- bài 2: xử lý đặt hàng
delimiter //
create procedure sp_place_order(
    in p_product_id int,
    in p_quantity int
)
begin
    declare v_stock int;
    start transaction;
    select stock into v_stock from products where product_id = p_product_id;
    if v_stock >= p_quantity then
        insert into orders (product_id, quantity, order_date) values (p_product_id, p_quantity, now());
        update products set stock = stock - p_quantity where product_id = p_product_id;
        commit;
    else
        rollback;
    end if;
end //
delimiter ;

-- bài 3: chuyển lương nhân viên
delimiter //
create procedure sp_pay_salary(in p_emp_id int)
begin
    declare v_salary decimal(10,2);
    declare v_fund_balance decimal(10,2);
    declare v_bank_error int default 0; -- giả định 0 là không lỗi

    start transaction;
    select salary into v_salary from employees where emp_id = p_emp_id;
    select balance into v_fund_balance from company_funds limit 1;

    if v_fund_balance >= v_salary then
        update company_funds set balance = balance - v_salary;
        insert into payroll (emp_id, amount, pay_date) values (p_emp_id, v_salary, now());
        -- kiểm tra lỗi ngân hàng giả định
        if v_bank_error = 0 then
            commit;
        else
            rollback;
        end if;
    else
        rollback;
    end if;
end //
delimiter ;

-- bài 4: đăng ký học phần
delimiter //
create procedure sp_enroll_student(
    in p_student_name varchar(50),
    in p_course_name varchar(100)
)
begin
    declare v_std_id int;
    declare v_crs_id int;
    declare v_seats int;

    start transaction;
    select student_id into v_std_id from students where student_name = p_student_name;
    select course_id, available_seats into v_crs_id, v_seats from courses where course_name = p_course_name;

    if v_seats > 0 then
        insert into enrollments (student_id, course_id) values (v_std_id, v_crs_id);
        update courses set available_seats = available_seats - 1 where course_id = v_crs_id;
        commit;
    else
        rollback;
    end if;
end //
delimiter ;

-- bài 5 & 6: mạng xã hội (đăng bài và like)
-- bài 5
start transaction;
insert into posts (user_id, content) values (1, 'nội dung bài viết mới');
update users set posts_count = posts_count + 1 where user_id = 1;
commit;

-- bài 6
start transaction;
insert into likes (post_id, user_id) values (1, 2);
update posts set likes_count = likes_count + 1 where post_id = 1;
commit;

-- bài 7: theo dõi người dùng
delimiter //
create procedure sp_follow_user(in p_follower_id int, in p_followed_id int)
begin
    declare exit handler for sqlexception rollback;
    start transaction;
    if p_follower_id <> p_followed_id then
        insert into followers (follower_id, followed_id) values (p_follower_id, p_followed_id);
        update users set following_count = following_count + 1 where user_id = p_follower_id;
        update users set followers_count = followers_count + 1 where user_id = p_followed_id;
        commit;
    else
        rollback;
    end if;
end //
delimiter ;

-- bài 8: đăng bình luận với savepoint
delimiter //
create procedure sp_post_comment(in p_post_id int, in p_user_id int, in p_content text)
begin
    declare exit handler for sqlexception
    begin
        rollback to after_insert;
    end;

    start transaction;
    insert into comments (post_id, user_id, content) values (p_post_id, p_user_id, p_content);
    savepoint after_insert;
    update posts set comments_count = comments_count + 1 where post_id = p_post_id;
    commit;
end //
delimiter ;