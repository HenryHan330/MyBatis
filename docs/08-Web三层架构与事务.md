# 08 Web 三层架构与事务

> 把 MyBatis 放回真实的 Web 项目里，最关键的只有一件事：**一次请求 = 一个 `SqlSession` = 一个事务**。

## 1. 需求：银行转账

`act-001` 给 `act-002` 转 1000 元：

```sql
update t_act set balance = balance - 1000 where actno = 'act-001';
update t_act set balance = balance + 1000 where actno = 'act-002';
```

两条 SQL 必须在**同一个事务**里：要么都成功，要么都回滚。

```sql
create table t_act(
  id      bigint primary key auto_increment,
  actno   varchar(255),
  balance decimal(10,2)
);
insert into t_act(actno, balance) values ('act-001', 5000), ('act-002', 5000);
```

## 2. 工程与依赖

- IDEA 创建 **Maven Web App**（打包方式 `war`），项目名 `mybatis-004-web`。
- 部署到 **Tomcat 10+**（Jakarta EE 9+）。

```xml
<dependencies>
    <!-- servlet api：Tomcat 10+ 用 jakarta.servlet-api 6.0.0 -->
    <dependency>
        <groupId>jakarta.servlet</groupId>
        <artifactId>jakarta.servlet-api</artifactId>
        <version>6.0.0</version>
        <scope>provided</scope>
    </dependency>
    <dependency>
        <groupId>mysql</groupId>
        <artifactId>mysql-connector-java</artifactId>
        <version>8.0.30</version>
    </dependency>
    <dependency>
        <groupId>org.mybatis</groupId>
        <artifactId>mybatis</artifactId>
        <version>3.5.19</version>
    </dependency>
    <dependency>
        <groupId>org.junit.jupiter</groupId>
        <artifactId>junit-jupiter</artifactId>
        <version>5.10.2</version>
        <scope>test</scope>
    </dependency>
</dependencies>
```

> ⚠️ **笔记原文的一处不一致**：pom 里引的是 `jakarta.servlet-api:6.0.0`（Tomcat 10+），
> 但 `AccountController` 里写的是 `import javax.servlet.*`，两者**不能混用**：
> - Tomcat 9 及以下：`javax.servlet-api:4.0.1` + `import javax.servlet.*`
> - Tomcat 10 及以上：`jakarta.servlet-api:6.0.0` + `import jakarta.servlet.*`
>
> 混用会报「程序包 javax.servlet 不存在」，或运行期 `ClassNotFoundException`。

## 3. 分层结构

```text
com.jkweilai.mybatis
├── pojo      Account
├── dao       AccountDao（接口）
├── service   AccountService（接口）/ impl.AccountServiceImpl
├── web       AccountController（Servlet）
└── utils     SqlSessionUtil
resources
├── mybatis-config.xml
├── AccountMapper.xml
├── jdbc.properties
└── index.html
```

### 3.1 `AccountMapper.xml`

```xml
<mapper namespace="com.jkweilai.mybatis.dao.AccountDao">
    <select id="selectByActno" resultType="account">
        select id, actno, balance from t_act where actno = #{actno}
    </select>

    <update id="updateByActno">
        update t_act set balance = #{balance} where actno = #{actno}
    </update>
</mapper>
```

### 3.2 dao 只留接口（实现交给 `getMapper`）

```java
public interface AccountDao {
    Account selectByActno(String actno);
    int updateByActno(Account account);
}
```

### 3.3 service 负责事务边界

```java
public class AccountServiceImpl implements AccountService {

    private final AccountDao accountDao = new AccountDaoImpl();

    @Override
    public void transfer(String fromActno, String toActno, BigDecimal money) {
        SqlSession sqlSession = SqlSessionUtil.openSession();
        try {
            Account from = accountDao.selectByActno(fromActno);
            if (from == null) throw new RuntimeException("转出账户不存在");
            Account to = accountDao.selectByActno(toActno);
            if (to == null) throw new RuntimeException("转入账户不存在");
            if (from.getBalance().compareTo(money) < 0) throw new RuntimeException("余额不足");

            from.setBalance(from.getBalance().subtract(money));
            to.setBalance(to.getBalance().add(money));
            accountDao.updateByActno(from);
            accountDao.updateByActno(to);

            sqlSession.commit();          // 全部成功才提交
        } catch (Exception e) {
            sqlSession.rollback();        // 出异常回滚
            throw new RuntimeException("转账失败", e);
        } finally {
            SqlSessionUtil.closeSqlSession();
        }
    }
}
```

### 3.4 Controller（Servlet）

```java
@WebServlet("/transfer")
public class AccountController extends HttpServlet {

    private final AccountService accountService = new AccountServiceImpl();

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        String fromActno = request.getParameter("fromActno");
        String toActno = request.getParameter("toActno");
        BigDecimal money = new BigDecimal(request.getParameter("money"));

        response.setContentType("text/html;charset=UTF-8");
        try {
            accountService.transfer(fromActno, toActno, money);
            response.getWriter().print("转账成功");
        } catch (Exception e) {
            response.getWriter().print("转账失败：" + e.getMessage());
        }
    }
}
```

## 4. 核心问题：为什么事务会失效？

**错误写法**（每个 dao 方法里各自 `openSession()`）：

```java
public Account selectByActno(String actno) {
    SqlSession sqlSession = sqlSessionFactory.openSession();  // ← 事务 A
    ...
}
public int updateByActno(Account a) {
    SqlSession sqlSession = sqlSessionFactory.openSession();  // ← 事务 B
    ...
}
```

结果：

- 每次 `openSession()` 都是**新连接、新事务**；
- service 里的 `commit()` 只提交了「最后一次」的那个会话；
- 转出成功、转入失败时，**转出的钱扣了但不会退回** ⇒ 事务彻底失效。

**正确做法**：用 `ThreadLocal` 让**同一次请求（同一个线程）**共用同一个 `SqlSession`：

```java
// SqlSessionUtil
public static SqlSession openSession() {
    SqlSession sqlSession = THREAD_LOCAL.get();
    if (sqlSession == null) {
        sqlSession = SQL_SESSION_FACTORY.openSession();
        THREAD_LOCAL.set(sqlSession);
    }
    return sqlSession;
}
```

```java
// dao 实现：只用，不关
public class AccountDaoImpl implements AccountDao {
    @Override
    public Account selectByActno(String actno) {
        return SqlSessionUtil.openSession()
                .getMapper(AccountDao.class)
                .selectByActno(actno);
    }
}
```

- **谁最上层（service）开事务，谁负责 `commit` / `rollback` / `close`**。
- dao 只管拿 session 用，**绝不 `close()`**。

## 5. 三个对象的作用域（再强调一次）

| 对象 | 作用域 | 线程安全性 | 说明 |
| --- | --- | --- | --- |
| `SqlSessionFactoryBuilder` | 方法 | 安全 | 用完即丢 |
| `SqlSessionFactory` | 应用（单例） | 安全 | 全局唯一 |
| `SqlSession` | 请求 / 方法 | **非线程安全** | 不能做成员变量、不能放 `HttpSession`、关闭必须放 `finally` |

## 6. 现代做法：交给 Spring

真实项目不会手写 `commit/rollback`：

```java
@Service
public class AccountServiceImpl implements AccountService {

    @Autowired
    private AccountDao accountDao;

    @Override
    @Transactional(rollbackFor = Exception.class)   // Spring 声明式事务
    public void transfer(String fromActno, String toActno, BigDecimal money) {
        // 只管业务，事务由 AOP 代理控制
    }
}
```

Spring 用 `ThreadLocal` 绑定 `SqlSession` / `Connection` 的机制与本节完全一致 ——
**理解了这个手写版，就理解了 `@Transactional` 为什么能生效**。

> 注意：`@Transactional` 默认只回滚 `RuntimeException`，抛受检异常不回滚，
> 所以规范写法是 `@Transactional(rollbackFor = Exception.class)`。

## 7. 本篇小结

1. Web 项目里 `SqlSession` 的生命周期 = **一次请求**，靠 `ThreadLocal` 实现。
2. **事务边界在 service**，dao 不提交、不关闭。
3. 事务失效的经典原因是「每次 dao 都新开 session」。
4. Spring 的 `@Transactional` 是把这套机制自动化了，原理相同。

